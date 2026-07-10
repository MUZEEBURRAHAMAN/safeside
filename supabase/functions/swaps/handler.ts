/**
 * GET swaps/product/:id/swaps — pure handler logic.
 *
 * "See a better option": close the loop no competitor closes (principle #4) —
 * turn a verdict into a concrete, ranked, restriction-safe better choice in the
 * SAME category. Kept free of Deno.serve / supabase-js so it is unit-testable
 * with injected deps (index.ts wires the real ones).
 *
 * Every ranking step and every "why better" fact is a DETERMINISTIC diff of
 * stored DB fields (CLAUDE.md #5 — the LLM never runs here; principle #1 —
 * every fact is sourced, from products.additives_tags + products.nutrients,
 * both OFF/USDA-sourced). Thin/empty results stay honest (never a dead-end).
 *
 * The response body decodes into ios/FoodScanner/Models.swift `SwapsResponse`.
 */

import additivesRisk from "../_shared/scoring/additives_risk.json" with {
  type: "json",
};
import { additiveCategory } from "../_shared/additives/category.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A product + its current score, as resolved by index.ts (impure) and fed to
 * the pure ranking here. `score` is null / `band` "unknown" when we have no
 * current-version score. */
export interface SwapProductRow {
  id: string;
  barcode: string | null;
  name: string;
  brand: string | null;
  imageURL: string | null;
  categoriesTags: string[];
  additivesTags: string[];
  allergensTags: string[];
  nutrients: Record<string, unknown>;
  score: number | null;
  band: string;
}

export interface Deps {
  /** Subject product + current score, or null when the id is not in products. */
  getSubject(id: string): Promise<SwapProductRow | null>;
  /** Same-category candidates (category overlap), each with its current score. */
  getCandidates(
    categoriesTags: string[],
    excludeId: string,
  ): Promise<SwapProductRow[]>;
  /** The caller's pantry product ids (user-scoped, RLS). Empty for guests. */
  getPantryProductIds(): Promise<Set<string>>;
  /** The caller's profile allergies (user-scoped, RLS). Empty for guests. */
  getAllergies(): Promise<string[]>;
  now(): number;
}

/** One ranked better option — decodes into Models.swift `SwapCandidate`. */
export interface SwapResult {
  id: string;
  barcode: string | null; // routes the "View" tap through ProductLoaderView(barcode:)
  name: string;
  brand: string | null;
  imageURL: string | null;
  score: number;
  band: string;
  delta: number;
  inPantry: boolean;
  whyBetter: string[];
}

// ---------------------------------------------------------------------------
// Tuning constants
// ---------------------------------------------------------------------------

const MAX_SWAPS = 5;
const MIN_STRONG = 2; // fewer than this → thin (client shows the honest note)
/** A nutrient must drop by more than this fraction to be worth mentioning. */
const NUTRIENT_DROP = 0.9;
const MAX_WHY_FACTS = 3;

/** Per-100 g nutrient fields we tout a reduction of, with their display word. */
const LOWER_NUTRIENTS: Array<[string, string]> = [
  ["sugars_100g", "sugar"],
  ["saturated-fat_100g", "saturated fat"],
  ["salt_100g", "salt"],
];

// ---------------------------------------------------------------------------
// CORS + JSON helpers (mirrors product/handler.ts)
// ---------------------------------------------------------------------------

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Additive risk table (for the moderate/higher gate + display eNumber)
// ---------------------------------------------------------------------------

interface RiskEntry {
  tier?: string;
  eNumber?: string;
}

const riskTable = additivesRisk as unknown as Record<string, RiskEntry>;

// ---------------------------------------------------------------------------
// Id extraction + helpers
// ---------------------------------------------------------------------------

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The id is the second-to-last path segment: /swaps/product/<id>/swaps
 * (works behind the platform prefix /functions/v1/... too). */
export function extractSubjectId(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter((s) => s !== "");
  if (segments.length < 2) return null;
  const candidate = segments[segments.length - 2];
  if (!candidate || candidate === "product") return null;
  return candidate;
}

/** Strip a leading `xx:` language prefix and lowercase (allergen/additive tags). */
function normTag(tag: string): string {
  return tag.replace(/^[a-z]{2}:/i, "").toLowerCase();
}

function asFiniteNumber(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

// ---------------------------------------------------------------------------
// Why-better — deterministic, sourced facts only (max 3). NO LLM.
// ---------------------------------------------------------------------------

/**
 * Facts explaining why `candidate` scores better than `subject`, drawn only
 * from stored DB fields:
 *  - Additive absence: an additive present in the subject but absent in the
 *    candidate, emitted ONLY for moderate/higher-tier reviewed additives
 *    (never tout removing a benign/unreviewed one). Grouped by INS class where
 *    the E-number gives one → "No colours E150d" (COPY_DECK §Swaps).
 *  - Lower nutrient: a per-100 g value that is meaningfully lower (> 10 %) with
 *    both values present as finite numbers → "lower saturated fat".
 * Capped at 3, additives first (matches the deck example ordering).
 */
export function whyBetter(
  subject: SwapProductRow,
  candidate: SwapProductRow,
): string[] {
  const facts: string[] = [];

  const candidateAdditives = new Set(candidate.additivesTags.map(normTag));
  for (const rawTag of subject.additivesTags) {
    const tag = rawTag.toLowerCase();
    if (candidateAdditives.has(normTag(rawTag))) continue; // still present
    const entry = riskTable[tag];
    if (entry?.tier !== "moderate" && entry?.tier !== "higher") continue;
    const eNumber = entry.eNumber ?? rawTag.replace(/^en:/, "").toUpperCase();
    const cls = additiveCategory(rawTag);
    facts.push(cls ? `No ${cls.toLowerCase()} ${eNumber}` : `No ${eNumber}`);
  }

  for (const [field, label] of LOWER_NUTRIENTS) {
    const s = asFiniteNumber(subject.nutrients[field]);
    const c = asFiniteNumber(candidate.nutrients[field]);
    if (s === null || c === null || s <= 0) continue;
    if (c < s * NUTRIENT_DROP) facts.push(`lower ${label}`);
  }

  return facts.slice(0, MAX_WHY_FACTS);
}

// ---------------------------------------------------------------------------
// Ranking — pure + deterministic
// ---------------------------------------------------------------------------

/**
 * Rank same-category candidates into better options for `subject`:
 *  1. Better: candidate score strictly > subject score (skip null/unknown).
 *  2. Restriction-safe: drop any whose allergens intersect `allergies`.
 *  3. Pantry-first, then delta, then score, then name (deterministic).
 *  4. Cap at MAX_SWAPS.
 * Returns the ranked list + whether allergen filtering removed anyone.
 */
export function rankSwaps(
  subject: SwapProductRow,
  candidates: SwapProductRow[],
  pantryIds: Set<string>,
  allergies: string[],
): { swaps: SwapResult[]; filteredForAllergies: boolean } {
  const subjectScore = subject.score ?? 0;
  const allergySet = new Set(allergies.map(normTag).filter((a) => a !== ""));

  let filteredForAllergies = false;
  const kept: SwapResult[] = [];

  for (const c of candidates) {
    // 1. Strictly better, with a real (known-band) score.
    if (c.score === null || c.band === "unknown") continue;
    if (c.score <= subjectScore) continue;

    // 2. Restriction-safe.
    if (allergySet.size > 0) {
      const conflict = c.allergensTags.some((t) => allergySet.has(normTag(t)));
      if (conflict) {
        filteredForAllergies = true;
        continue;
      }
    }

    kept.push({
      id: c.id,
      barcode: c.barcode,
      name: c.name,
      brand: c.brand,
      imageURL: c.imageURL,
      score: c.score,
      band: c.band,
      delta: c.score - subjectScore,
      inPantry: pantryIds.has(c.id),
      whyBetter: whyBetter(subject, c),
    });
  }

  // 3. Stable, deterministic ordering: pantry-first → delta → score → name.
  kept.sort((a, b) => {
    if (a.inPantry !== b.inPantry) return a.inPantry ? -1 : 1;
    if (a.delta !== b.delta) return b.delta - a.delta;
    if (a.score !== b.score) return b.score - a.score;
    return a.name.localeCompare(b.name);
  });

  return { swaps: kept.slice(0, MAX_SWAPS), filteredForAllergies };
}

// ---------------------------------------------------------------------------
// Category display label
// ---------------------------------------------------------------------------

/** A human label from the primary (first) category tag: "en:chocolate-spreads"
 * → "Chocolate spreads". null when the subject has no category. */
export function categoryLabel(categoriesTags: string[]): string | null {
  const primary = categoriesTags[0];
  if (!primary) return null;
  const words = normTag(primary).replace(/-/g, " ").trim();
  if (words === "") return null;
  return words.charAt(0).toUpperCase() + words.slice(1);
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleSwaps(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // The platform verifies the JWT; we still require the header so unauthenticated
  // local calls fail loudly.
  if (!req.headers.get("Authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  const id = extractSubjectId(req.url);
  if (!id || !UUID_RE.test(id)) {
    return json({ error: "invalid_id" }, 400);
  }

  const subject = await deps.getSubject(id);
  if (!subject) {
    return json({ error: "not_found" }, 404);
  }

  const category = categoryLabel(subject.categoriesTags);
  const subjectScore = subject.score ?? 0;

  // No category → we cannot honestly group "same category" swaps (principle #4:
  // an honest empty state, never a fabricated match).
  if (subject.categoriesTags.length === 0) {
    return json({
      category: null,
      subjectScore,
      filteredForAllergies: false,
      swaps: [],
      thin: true,
    });
  }

  const [candidates, pantryIds, allergies] = await Promise.all([
    deps.getCandidates(subject.categoriesTags, subject.id),
    deps.getPantryProductIds(),
    deps.getAllergies(),
  ]);

  const { swaps, filteredForAllergies } = rankSwaps(
    subject,
    candidates,
    pantryIds,
    allergies,
  );

  return json({
    category,
    subjectScore,
    filteredForAllergies,
    swaps,
    thin: swaps.length < MIN_STRONG,
  });
}
