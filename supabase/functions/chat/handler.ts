/**
 * POST /chat — grounded product Q&A (BACKEND_SPEC §4, MASTER_PLAN Phase 3).
 *
 * Answers a user's questions about ONE specific scanned product ("Is this
 * safe?", "Can my kid eat this?", "Why this score?", "Better alternatives?")
 * grounded ONLY in that product's real data. This is NOT a general chatbot and
 * NOT medical advice — it re-phrases facts the backend already holds, exactly
 * like the ingredient endpoint (docs/AI_INGREDIENT_EXPLANATION.md): retrieval,
 * not generation.
 *
 * Grounding context (assembled server-side from the DB by productId):
 *   1. The product (name/brand/nutrients/NOVA/Nutri-Score/additives/allergens).
 *   2. Its latest score_results breakdown (sub-scores + weights + the
 *      plain-language factor details + sources).
 *   3. The matching ingredient_kb entries for its additives/ingredients.
 *   4. Optionally the caller's profile (allergies/health flags/diet) for
 *      relevance — read under RLS from the JWT's user, else skipped.
 *
 * Guardrails (ship-blocking, mirror the ingredients endpoint):
 *   - Bounded system prompt: answer ONLY from the provided data; if it's not
 *     there, say so — never use outside knowledge.
 *   - NOT medical advice: never diagnose/prescribe/"safe for your condition".
 *     A "not medical advice" disclaimer is ALWAYS returned.
 *   - Banned-word filter (reused from _shared/kb/kb.ts) on the model output.
 *   - No LLM key → graceful canned reply (never crash). Output tokens capped,
 *     history bounded to the last few turns.
 *
 * Deployed function name `chat` (no slash) → client path POST /functions/v1/chat.
 * Everything here is pure + I/O-free except through injected `Deps`, so the
 * grounding + guardrails run offline in the test suite.
 */

import type { LlmClient, LlmMessage } from "../_shared/llm.ts";
import { hasBannedWord, type KbEntry, type KbSource } from "../_shared/kb/kb.ts";
import { buildCandidates, type ProductIngredientsRow } from "../ingredients/handler.ts";
import type { ScoreFactor } from "../_shared/scoring/engine.ts";

// ---------------------------------------------------------------------------
// CORS + JSON helpers
// ---------------------------------------------------------------------------

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Constants (cost/safety bounds + fixed copy)
// ---------------------------------------------------------------------------

/** Exact disclaimer (CONTRACT — iOS depends on it) — from COPY_DECK.md. */
export const DISCLAIMER = "Information only — not medical advice.";

/** Graceful fallback when the LLM key is missing / the model errors. */
export const CANNED_UNAVAILABLE =
  "AI chat is unavailable right now. You can still see this product's score " +
  "breakdown and ingredient details.";

/** Returned when the model output trips the banned-word filter. */
export const CANNED_FILTERED =
  "I can only describe this product's data in neutral terms. Take a look at " +
  "the score breakdown and ingredient details, and check with a health " +
  "professional for anything about your own health.";

/** Keep only the last N turns of history (cost + prompt-size bound). */
export const MAX_HISTORY_MESSAGES = 8;
/** Trim any single message so a pasted wall of text can't blow the budget. */
export const MAX_MESSAGE_CHARS = 2000;
/** Hard cap on completion tokens (BACKEND_SPEC §5 cost control). */
export const MAX_OUTPUT_TOKENS = 600;

/** Per-user sliding-window rate limit (Chunk 4, Task 4). */
export const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute sliding window
export const RATE_LIMIT_MAX = 10; // requests per user per window (tunable)

/** Calm 429 body copy — verbatim from docs/COPY_DECK.md §"Offline & limits". */
export const CHAT_RATE_LIMITED =
  "You've asked a lot in a short time. Give it a minute and try again.";

export interface RateDecision {
  allowed: boolean;
  retryAfterSeconds: number;
}

/**
 * Pure sliding-window check over epoch-ms timestamps. Blocks once `max`
 * requests fall inside the last `windowMs`; `retryAfterSeconds` is how long
 * until the oldest in-window hit ages out (so a client knows exactly when to
 * retry). No I/O — unit-tested offline.
 */
export function withinRateLimit(
  timestamps: number[],
  now: number,
  windowMs: number,
  max: number,
): RateDecision {
  const inWindow = timestamps.filter((t) => now - t < windowMs).sort((a, b) => a - b);
  if (inWindow.length < max) return { allowed: true, retryAfterSeconds: 0 };
  const oldest = inWindow[0];
  const retryAfterSeconds = Math.max(1, Math.ceil((windowMs - (now - oldest)) / 1000));
  return { allowed: false, retryAfterSeconds };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ChatRole = "user" | "assistant";

export interface ChatMessage {
  role: ChatRole;
  content: string;
}

/** The product fields relevant to grounding (snake→camel done at the edge). */
export interface ChatProductRow {
  name: string;
  brand: string | null;
  novaGroup: number | null;
  nutriscoreGrade: string | null;
  servingSize: string | null;
  nutrients: Record<string, unknown>;
  additivesTags: string[];
  allergensTags: string[];
  ingredientsText: string | null;
}

/** Latest score_results row, flattened for the prompt. */
export interface ChatScoreRow {
  score: number | null;
  band: string;
  confidence: string;
  factors: ScoreFactor[];
}

/** The caller's profile — only the fields that make an answer relevant. */
export interface ChatProfile {
  allergies: string[];
  healthFlags: string[];
  dietPattern: string | null;
}

export interface Deps {
  getProduct(id: string): Promise<ChatProductRow | null>;
  getScore(productId: string): Promise<ChatScoreRow | null>;
  getKb(): Promise<KbEntry[]>;
  /**
   * The caller's own profile (RLS-scoped to the JWT user), or null when there
   * is no profile / it can't be read. Optional: absent → no personalization.
   */
  getProfile?(): Promise<ChatProfile | null>;
  /** null when LLM_API_KEY is unset → graceful canned reply. */
  llm: LlmClient | null;
  now(): number;
  // --- Rate limiting (all optional → absent = limiter skipped, as in unit
  // tests and when there is no authenticated user). Wired in index.ts against
  // the service-role `chat_rate_events` ledger. ---
  /** The caller's stable id — JWT `sub` (anon uids included), or null. */
  userId?(): string | null;
  /** Epoch-ms timestamps of this user's requests in the window (service role). */
  recentChatRequests?(userId: string): Promise<number[]>;
  /** Record one ACCEPTED request for this user at `atMs` (service role). */
  recordChatRequest?(userId: string, atMs: number): Promise<void>;
}

// ---------------------------------------------------------------------------
// Grounding context (what the model is allowed to see)
// ---------------------------------------------------------------------------

/** KB facts trimmed to the vetted fields we ground on (no fabrication room). */
interface GroundedIngredient {
  name: string;
  what: string | null;
  whyUsed: string | null;
  safety: string | null;
  riskTier: string;
  whoShouldAvoid: string[];
  misconceptions: string[];
  sources: KbSource[];
}

export interface GroundingContext {
  product: {
    name: string;
    brand: string | null;
    novaGroup: number | null;
    nutriscoreGrade: string | null;
    servingSize: string | null;
    nutrients: Record<string, unknown>;
    additivesTags: string[];
    allergens: string[];
    ingredientsText: string | null;
  };
  score: {
    score: number | null;
    band: string;
    confidence: string;
    factors: ScoreFactor[];
  } | null;
  ingredientFacts: GroundedIngredient[];
  profile: ChatProfile | null;
}

/** Drop enrichment/provenance noise so the prompt stays about the food. */
function cleanNutrients(n: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(n)) {
    if (k === "_enrichment" || k === "_meta") continue;
    out[k] = v;
  }
  return out;
}

/** Strip the "en:" style locale prefix from allergen tags for display. */
function stripPrefix(tags: string[]): string[] {
  return tags.map((t) => t.replace(/^[a-z]{2}:/, ""));
}

/**
 * Resolve the product's additives + ingredient tokens against the KB (reusing
 * the ingredients endpoint's exact resolution) and keep only the entries we
 * actually have vetted facts for. Unknown ingredients contribute NO facts —
 * the model must not invent them.
 */
export function resolveIngredientFacts(
  row: ProductIngredientsRow,
  kb: KbEntry[],
): GroundedIngredient[] {
  const facts: GroundedIngredient[] = [];
  for (const { entry } of buildCandidates(row, kb)) {
    if (entry === null) continue;
    facts.push({
      name: entry.names[0] ?? entry.id,
      what: entry.what,
      whyUsed: entry.why_used,
      safety: entry.safety,
      riskTier: entry.risk_tier,
      whoShouldAvoid: entry.who_should_avoid,
      misconceptions: entry.misconceptions,
      sources: entry.sources,
    });
  }
  return facts;
}

export function buildGroundingContext(
  product: ChatProductRow,
  score: ChatScoreRow | null,
  kb: KbEntry[],
  profile: ChatProfile | null,
): GroundingContext {
  const row: ProductIngredientsRow = {
    additivesTags: product.additivesTags,
    ingredientsText: product.ingredientsText,
  };
  return {
    product: {
      name: product.name,
      brand: product.brand,
      novaGroup: product.novaGroup,
      nutriscoreGrade: product.nutriscoreGrade,
      servingSize: product.servingSize,
      nutrients: cleanNutrients(product.nutrients),
      additivesTags: product.additivesTags,
      allergens: stripPrefix(product.allergensTags),
      ingredientsText: product.ingredientsText,
    },
    score: score === null ? null : {
      score: score.score,
      band: score.band,
      confidence: score.confidence,
      factors: score.factors,
    },
    ingredientFacts: resolveIngredientFacts(row, kb),
    // Only surface profile fields the model can act on; empty → drop it.
    profile: profile &&
        (profile.allergies.length > 0 || profile.healthFlags.length > 0 ||
          profile.dietPattern)
      ? profile
      : null,
  };
}

/**
 * Deterministic citation list — the sources the answer is allowed to lean on.
 * Built from the score factors + resolved KB entries (NOT from the model, so a
 * source/URL can never be fabricated). Deduped by name+url.
 */
export function collectSources(context: GroundingContext): KbSource[] {
  const seen = new Set<string>();
  const out: KbSource[] = [];
  const add = (s: KbSource) => {
    const key = `${s.name}|${s.url ?? ""}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ name: s.name, url: s.url });
  };
  for (const f of context.score?.factors ?? []) {
    for (const s of f.sources) add(s);
  }
  for (const ing of context.ingredientFacts) {
    for (const s of ing.sources) add(s);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Bounded prompt
// ---------------------------------------------------------------------------

export const SYSTEM_PROMPT = [
  "You are a calm, neutral assistant that answers questions about ONE specific packaged food product, using ONLY the PRODUCT DATA provided below.",
  "Ground every answer in that data (the product fields, its score breakdown, and the vetted ingredient facts). If the answer is not in the provided data, say you don't have that information for this product — do NOT use outside knowledge, and never guess or invent facts, numbers, studies, or sources.",
  "This is general information, NOT medical advice. Never diagnose, prescribe, or say a product is 'safe for' someone's condition, pregnancy, age, or diet. For questions like 'can my kid/pregnant/diabetic person eat this', give the factual data (e.g. which additives and their reviewed tier, which allergens are present) and add that this is general information, not medical advice, and to check with a professional.",
  "Presence of an ingredient or additive is not the same as harm — be risk- and dose-aware and do not imply danger the data does not support.",
  "Use calm, non-shaming language. Never use the words: bad, toxic, poison, poisonous, junk, clean, cheat, dangerous.",
  "If the user flags an allergy, health condition, or diet in their profile that a listed ingredient/allergen is relevant to, note it plainly; otherwise don't invent relevance.",
  "Be concise (a few short sentences). Refer to the named sources in the data when you cite something.",
  'Return ONLY a JSON object of the form {"reply": "<your answer as plain text>"}.',
].join(" ");

/**
 * Build the messages sent to the model: the bounded system prompt with the
 * grounding context inlined, then the (already bounded) conversation history.
 */
export function buildMessages(
  context: GroundingContext,
  history: ChatMessage[],
): LlmMessage[] {
  const system: LlmMessage = {
    role: "system",
    content: `${SYSTEM_PROMPT}\n\nPRODUCT DATA (your only source of truth):\n${
      JSON.stringify(context, null, 2)
    }`,
  };
  const turns: LlmMessage[] = history.map((m) => ({
    role: m.role,
    content: m.content,
  }));
  return [system, ...turns];
}

/**
 * Normalize + bound the client's message history: keep only valid user/
 * assistant turns with non-empty content, trim each, and keep the last N.
 */
export function boundHistory(messages: ChatMessage[]): ChatMessage[] {
  const clean: ChatMessage[] = [];
  for (const m of messages) {
    if (!m || (m.role !== "user" && m.role !== "assistant")) continue;
    if (typeof m.content !== "string") continue;
    const content = m.content.trim().slice(0, MAX_MESSAGE_CHARS);
    if (content === "") continue;
    clean.push({ role: m.role, content });
  }
  return clean.slice(-MAX_HISTORY_MESSAGES);
}

/** Extract the reply string from the model's JSON output, or null if invalid. */
export function parseReply(raw: string): string | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const reply = (parsed as { reply?: unknown }).reply;
  if (typeof reply !== "string" || reply.trim() === "") return null;
  return reply.trim();
}

// ---------------------------------------------------------------------------
// Orchestration (network-free; the LLM + DB arrive via Deps)
// ---------------------------------------------------------------------------

/**
 * Produce the grounded reply text. Never throws:
 *   - llm === null (no key) → canned "unavailable".
 *   - LLM error / unparsable output → canned "unavailable".
 *   - banned word in the reply → canned "filtered" (reuses hasBannedWord).
 *   - otherwise → the model's grounded reply.
 * The disclaimer + deterministic sources are attached by the caller regardless.
 */
export async function generateReply(
  context: GroundingContext,
  history: ChatMessage[],
  llm: LlmClient | null,
): Promise<string> {
  if (llm === null) return CANNED_UNAVAILABLE;

  const messages = buildMessages(context, history);

  let raw: string;
  try {
    raw = await llm.complete(messages, { maxTokens: MAX_OUTPUT_TOKENS });
  } catch {
    return CANNED_UNAVAILABLE;
  }

  const reply = parseReply(raw);
  if (reply === null) return CANNED_UNAVAILABLE;

  // Ship-blocking guardrail: any fear word → discard the model output.
  if (hasBannedWord(reply)) return CANNED_FILTERED;

  return reply;
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

interface ParsedBody {
  productId: string;
  messages: ChatMessage[];
}

function parseBody(body: unknown): ParsedBody | { error: string } {
  if (typeof body !== "object" || body === null) {
    return { error: "invalid_request" };
  }
  const b = body as { productId?: unknown; messages?: unknown };
  if (typeof b.productId !== "string" || !UUID_RE.test(b.productId)) {
    return { error: "invalid_product_id" };
  }
  if (!Array.isArray(b.messages)) {
    return { error: "invalid_request" };
  }
  const messages = boundHistory(b.messages as ChatMessage[]);
  if (messages.length === 0 || !messages.some((m) => m.role === "user")) {
    return { error: "invalid_request" };
  }
  return { productId: b.productId, messages };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleChat(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!req.headers.get("Authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  // Per-user sliding-window rate limit (skipped when the ledger deps or user id
  // are absent → backward-compatible with the offline unit tests). We record
  // only ACCEPTED requests below, so a 429'd request never extends its window.
  const uid = deps.userId?.() ?? null;
  if (uid && deps.recentChatRequests && deps.recordChatRequest) {
    const now = deps.now();
    const recent = await deps.recentChatRequests(uid);
    const decision = withinRateLimit(recent, now, RATE_LIMIT_WINDOW_MS, RATE_LIMIT_MAX);
    if (!decision.allowed) {
      return new Response(
        JSON.stringify({
          error: "rate_limited",
          retryAfterSeconds: decision.retryAfterSeconds,
          reply: CHAT_RATE_LIMITED,
          disclaimer: DISCLAIMER,
        }),
        {
          status: 429,
          headers: {
            ...CORS_HEADERS,
            "Content-Type": "application/json",
            "Retry-After": String(decision.retryAfterSeconds),
          },
        },
      );
    }
    await deps.recordChatRequest(uid, now);
  }

  let rawBody: unknown;
  try {
    rawBody = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const parsed = parseBody(rawBody);
  if ("error" in parsed) {
    return json({ error: parsed.error }, 400);
  }

  const product = await deps.getProduct(parsed.productId);
  if (product === null) {
    return json({ error: "not_found" }, 404);
  }

  const [score, kb] = await Promise.all([
    deps.getScore(parsed.productId),
    deps.getKb(),
  ]);

  // Profile is best-effort personalization — never fail the chat over it.
  let profile: ChatProfile | null = null;
  if (deps.getProfile) {
    try {
      profile = await deps.getProfile();
    } catch {
      profile = null;
    }
  }

  const context = buildGroundingContext(product, score, kb, profile);
  const sources = collectSources(context);
  const reply = await generateReply(context, parsed.messages, deps.llm);

  return json({ reply, sources, disclaimer: DISCLAIMER });
}
