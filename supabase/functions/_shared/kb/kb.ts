/**
 * Ingredient Knowledge Base — types, guardrails, and the bounded LLM rewrite.
 *
 * This is the credibility core of the app (docs/AI_INGREDIENT_EXPLANATION.md).
 * The rules enforced here, in code, are ship-blocking:
 *
 *   1. RETRIEVAL, NOT GENERATION. No KB entry → no explanation (unknown state).
 *      The LLM only ever rewrites fields we already hold.
 *   2. NO FABRICATION FOR MISSING FIELDS. If a KB field is empty, the output
 *      for that field stays null ("limited") regardless of what the LLM says.
 *   3. STRUCTURED FACTS COME FROM THE KB, NOT THE LLM. risk_tier, sources,
 *      who_should_avoid, misconceptions, and found_in are copied verbatim from
 *      the KB. The LLM may only re-phrase the three prose fields
 *      (what / why_used / safety). This shrinks the hallucination surface to
 *      nearly zero and makes the guardrails testable.
 *   4. RISK CONSISTENCY. The displayed risk_tier ALWAYS equals the KB/scoring
 *      tier — the LLM can never upgrade or downgrade it.
 *   5. BANNED-WORD FILTER. If any fear word slips into the rewrite, the whole
 *      LLM output is discarded and we fall back to the raw (vetted) KB text.
 *
 * Everything here is pure and network-free; the LLM arrives as an injected
 * `LlmClient` so the guardrail suite runs offline.
 */

import type { LlmClient, LlmMessage } from "../llm.ts";

export const KB_VERSION = "1.0";
export const DEFAULT_LOCALE = "en";

export type RiskTier = "low" | "moderate" | "higher";
export type Confidence = "high" | "limited";

export interface KbSource {
  name: string;
  url: string | null;
}

/** A row of `ingredient_kb` (snake_case matches the DB + seed JSON). */
export interface KbEntry {
  id: string;
  names: string[];
  what: string | null;
  why_used: string | null;
  safety: string | null;
  risk_tier: RiskTier;
  who_should_avoid: string[];
  misconceptions: string[];
  found_in: string[];
  sources: KbSource[];
  confidence: Confidence;
  last_reviewed: string | null;
  kb_version: string;
}

/** Output shape — decodes into ios/FoodScanner/Models.swift `Ingredient`. */
export interface IngredientOut {
  name: string;
  what: string | null;
  whyUsed: string | null;
  safety: string | null;
  riskTier: string | null;
  whoShouldAvoid: string[];
  misconceptions: string[];
  foundIn: string[];
  sources: KbSource[];
  confidence: Confidence;
}

// ---------------------------------------------------------------------------
// Banned-word filter (docs/COPY_DECK.md + AI spec §4/§5)
// ---------------------------------------------------------------------------

export const BANNED_WORDS = [
  "bad",
  "toxic",
  "poison",
  "poisonous",
  "junk",
  "clean",
  "cheat",
  "dangerous",
] as const;

const BANNED_RE = new RegExp(`\\b(${BANNED_WORDS.join("|")})\\b`, "i");

/** True if any banned fear word appears (whole-word, case-insensitive). */
export function hasBannedWord(text: string): boolean {
  return BANNED_RE.test(text);
}

function anyBanned(strings: (string | null)[]): boolean {
  return strings.some((s) => s !== null && hasBannedWord(s));
}

// ---------------------------------------------------------------------------
// KB → output mappers
// ---------------------------------------------------------------------------

const UNKNOWN_MESSAGE = "We don't have vetted info on this ingredient yet.";

/** Raw KB fields verbatim — the safe fallback and the no-LLM path. */
export function rawKbToIngredient(entry: KbEntry): IngredientOut {
  return {
    name: entry.names[0] ?? entry.id,
    what: entry.what,
    whyUsed: entry.why_used,
    safety: entry.safety,
    riskTier: entry.risk_tier,
    whoShouldAvoid: entry.who_should_avoid,
    misconceptions: entry.misconceptions,
    foundIn: entry.found_in,
    sources: entry.sources,
    confidence: entry.confidence,
  };
}

/** The "no vetted info" limited state — never a fabricated explanation. */
export function unknownIngredient(name: string): IngredientOut {
  return {
    name,
    what: UNKNOWN_MESSAGE,
    whyUsed: null,
    safety: null,
    riskTier: null,
    whoShouldAvoid: [],
    misconceptions: [],
    foundIn: [],
    sources: [],
    confidence: "limited",
  };
}

// ---------------------------------------------------------------------------
// Bounded prompt (docs/AI_INGREDIENT_EXPLANATION.md §4)
// ---------------------------------------------------------------------------

export const SYSTEM_PROMPT = [
  "You rewrite vetted facts about a food ingredient into plain, calm, neutral language.",
  "Explain ONLY from the provided facts. If a field is missing or empty, leave it empty — never fill gaps from your own knowledge.",
  "Do not add facts, numbers, studies, or safety verdicts that are not in the provided facts.",
  "Be risk- and dose-aware: presence in a food is not the same as harm. Do not imply danger the facts do not support.",
  "Never use the words: bad, toxic, poison, poisonous, junk, clean, cheat, dangerous. No shaming, no fear.",
  "Do not give medical advice or a diagnosis.",
  'Return ONLY a JSON object with exactly these string keys: "what", "whyUsed", "safety". Each value is a plain-language rewrite of the matching provided fact, or an empty string if that fact was not provided.',
].join(" ");

export function buildUserPrompt(entry: KbEntry): string {
  const facts = {
    name: entry.names[0] ?? entry.id,
    what: entry.what ?? "",
    whyUsed: entry.why_used ?? "",
    safety: entry.safety ?? "",
  };
  return [
    "Rewrite these provided facts. Leave a field empty if its provided value is empty.",
    "PROVIDED FACTS:",
    JSON.stringify(facts, null, 2),
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Guardrail enforcement over an LLM rewrite
// ---------------------------------------------------------------------------

interface LlmProse {
  what?: unknown;
  whyUsed?: unknown;
  safety?: unknown;
}

function cleanString(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

/**
 * Merge an LLM prose rewrite onto a KB entry under the guardrails.
 * A prose field is used ONLY when the corresponding KB field is non-empty
 * (rule 2) and the rewrite is non-empty; otherwise the KB value/null wins.
 * All structured fields + risk_tier come from the KB (rules 3, 4). Returns
 * the raw-KB output unchanged when the rewrite trips the banned-word filter
 * (rule 5).
 */
export function applyRewrite(entry: KbEntry, prose: LlmProse): IngredientOut {
  const base = rawKbToIngredient(entry);

  const what = entry.what !== null ? cleanString(prose.what) ?? entry.what : null;
  const whyUsed = entry.why_used !== null
    ? cleanString(prose.whyUsed) ?? entry.why_used
    : null;
  const safety = entry.safety !== null ? cleanString(prose.safety) ?? entry.safety : null;

  // Rule 5: any banned word in the rewrite → discard, keep vetted raw KB.
  if (anyBanned([what, whyUsed, safety])) {
    return base;
  }

  return {
    ...base,
    what,
    whyUsed,
    safety,
  };
}

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

/**
 * Produce the explanation for one KB entry.
 * - `llm === null` (no API key) → raw KB fields verbatim (graceful, sourced).
 * - LLM error / invalid JSON / banned words → raw KB fallback (never throws).
 * - Otherwise → guarded rewrite.
 */
export async function explainIngredient(
  entry: KbEntry,
  llm: LlmClient | null,
): Promise<IngredientOut> {
  if (llm === null) {
    return rawKbToIngredient(entry);
  }

  const messages: LlmMessage[] = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: buildUserPrompt(entry) },
  ];

  let raw: string;
  try {
    raw = await llm.complete(messages);
  } catch {
    return rawKbToIngredient(entry);
  }

  let prose: LlmProse;
  try {
    prose = JSON.parse(raw) as LlmProse;
  } catch {
    return rawKbToIngredient(entry);
  }

  return applyRewrite(entry, prose);
}

// ---------------------------------------------------------------------------
// KB lookup helpers (used by the ingredients endpoint)
// ---------------------------------------------------------------------------

/** Normalize a free-text ingredient token to the OFF tag convention. */
export function toIngredientId(token: string): string {
  const slug = token
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `en:${slug}`;
}

/** Build id + lowercased-name lookup maps over a KB list. */
export function buildKbIndex(entries: KbEntry[]): {
  byId: Map<string, KbEntry>;
  byName: Map<string, KbEntry>;
} {
  const byId = new Map<string, KbEntry>();
  const byName = new Map<string, KbEntry>();
  for (const entry of entries) {
    byId.set(entry.id.toLowerCase(), entry);
    for (const name of entry.names) {
      byName.set(name.toLowerCase().trim(), entry);
    }
  }
  return { byId, byName };
}
