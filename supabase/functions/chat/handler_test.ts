/**
 * POST /chat handler tests — fake deps (no network, no DB, mocked LLM).
 *
 * Covers the grounding + guardrail invariants that ship-block this endpoint:
 * grounded prompt assembly, banned-word / no-medical-advice handling, no
 * fabrication of ungrounded facts, graceful degradation without an LLM key,
 * and the 404 / validation paths. The LLM and DB arrive through Deps so every
 * assertion runs offline.
 */

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import type { LlmClient, LlmMessage } from "../_shared/llm.ts";
import { KB_VERSION, type KbEntry } from "../_shared/kb/kb.ts";
import type { ScoreFactor } from "../_shared/scoring/engine.ts";
import {
  boundHistory,
  buildGroundingContext,
  buildMessages,
  CANNED_FILTERED,
  CANNED_UNAVAILABLE,
  CHAT_RATE_LIMITED,
  type ChatMessage,
  type ChatProductRow,
  type ChatProfile,
  type ChatScoreRow,
  collectSources,
  type Deps,
  DISCLAIMER,
  generateReply,
  handleChat,
  MAX_HISTORY_MESSAGES,
  parseReply,
  RATE_LIMIT_MAX,
  resolveIngredientFacts,
  SYSTEM_PROMPT,
  withinRateLimit,
} from "./handler.ts";

const PRODUCT_ID = "33333333-3333-3333-3333-333333333333";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function kbEntry(overrides: Partial<KbEntry>): KbEntry {
  return {
    id: "en:e621",
    names: ["Monosodium glutamate", "MSG", "E621"],
    what: "A flavour enhancer.",
    why_used: "Adds a savoury (umami) taste.",
    safety: "EFSA set a group ADI for glutamates in 2017.",
    risk_tier: "moderate",
    who_should_avoid: [],
    misconceptions: ["MSG is not linked to the symptoms often blamed on it."],
    found_in: ["savoury snacks", "soups"],
    sources: [{
      name: "EFSA re-evaluation of glutamates (2017)",
      url: "https://www.efsa.europa.eu/en/efsajournal/pub/4910",
    }],
    confidence: "high",
    last_reviewed: "2026-07",
    kb_version: KB_VERSION,
    ...overrides,
  };
}

const KB: KbEntry[] = [
  kbEntry({}),
  kbEntry({
    id: "en:milk",
    names: ["Milk", "Whole milk"],
    what: "A dairy liquid.",
    why_used: "Adds protein and creaminess.",
    safety: "Milk is a common allergen.",
    risk_tier: "low",
    who_should_avoid: ["people with a milk allergy"],
    misconceptions: [],
    found_in: ["dairy products"],
    sources: [{ name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov/" }],
  }),
];

const FACTORS: ScoreFactor[] = [
  {
    name: "Processing",
    subScore: 20,
    weight: 0.5,
    detail: "NOVA group 4 (ultra-processed food).",
    sources: [{
      name: "NOVA classification (via Open Food Facts)",
      url: "https://world.openfoodfacts.org/nova",
    }],
  },
  {
    name: "Additives",
    subScore: 94,
    weight: 0.15,
    detail: "1 additive reviewed: 1 moderate-concern additive.",
    sources: [{
      name: "Curated additive review table v1.0 (EFSA / FDA / JECFA reviews)",
      url: null,
    }],
  },
];

function productRow(overrides: Partial<ChatProductRow> = {}): ChatProductRow {
  return {
    name: "Crunchy Cheese Snacks",
    brand: "ACME",
    novaGroup: 4,
    nutriscoreGrade: "d",
    servingSize: "30g",
    nutrients: {
      "energy-kcal_100g": 520,
      "salt_100g": 2.1,
      "_enrichment": { source: "usda", fdcId: 123 },
    },
    additivesTags: ["en:e621"],
    allergensTags: ["en:milk"],
    ingredientsText: "Corn, cheese, milk, flavour enhancer (E621), salt",
    ...overrides,
  };
}

function scoreRow(overrides: Partial<ChatScoreRow> = {}): ChatScoreRow {
  return {
    score: 41,
    band: "low",
    confidence: "high",
    factors: FACTORS,
    ...overrides,
  };
}

/** LLM that always returns the same JSON string; records the messages it saw. */
function fakeLlm(jsonOut: string): { llm: LlmClient; seen: LlmMessage[][] } {
  const seen: LlmMessage[][] = [];
  const llm: LlmClient = {
    complete(messages: LlmMessage[]) {
      seen.push(messages);
      return Promise.resolve(jsonOut);
    },
  };
  return { llm, seen };
}

function baseDeps(overrides: Partial<Deps> = {}): Deps {
  return {
    getProduct: (_id) => Promise.resolve(productRow()),
    getScore: (_id) => Promise.resolve(scoreRow()),
    getKb: () => Promise.resolve(KB),
    llm: fakeLlm('{"reply":"Here is what the data shows."}').llm,
    now: () => 0,
    ...overrides,
  };
}

function chatReq(
  body: unknown,
  opts: { method?: string; auth?: boolean } = {},
): Request {
  const { method = "POST", auth = true } = opts;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (auth) headers["Authorization"] = "Bearer test-jwt";
  return new Request("https://x.functions.supabase.co/chat", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const ASK: ChatMessage[] = [{ role: "user", content: "Is this safe for my kid?" }];

// ---------------------------------------------------------------------------
// 1. Grounding — the assembled prompt carries the product's real fields + KB
// ---------------------------------------------------------------------------

Deno.test("grounding context includes the product's real fields, score, and KB facts", () => {
  const ctx = buildGroundingContext(productRow(), scoreRow(), KB, null);

  assertEquals(ctx.product.name, "Crunchy Cheese Snacks");
  assertEquals(ctx.product.novaGroup, 4);
  assertEquals(ctx.product.nutriscoreGrade, "d");
  assertEquals(ctx.product.allergens, ["milk"]); // prefix stripped
  assertEquals(ctx.score?.score, 41);
  assertEquals(ctx.score?.factors.length, 2);

  // Both the additive (via tag) and milk (via ingredient text) are grounded.
  const names = ctx.ingredientFacts.map((f) => f.name).sort();
  assertEquals(names, ["Milk", "Monosodium glutamate"]);
  const msg = ctx.ingredientFacts.find((f) => f.name === "Monosodium glutamate")!;
  assertEquals(msg.riskTier, "moderate");
  assert(msg.sources[0].name.includes("EFSA"));
});

Deno.test("enrichment/provenance noise is stripped from the grounded nutrients", () => {
  const ctx = buildGroundingContext(productRow(), scoreRow(), KB, null);
  assertEquals("_enrichment" in ctx.product.nutrients, false);
  assertEquals(ctx.product.nutrients["salt_100g"], 2.1);
});

Deno.test("buildMessages inlines the grounding context into a bounded system prompt", () => {
  const ctx = buildGroundingContext(productRow(), scoreRow(), KB, null);
  const messages = buildMessages(ctx, ASK);

  assertEquals(messages[0].role, "system");
  // System prompt carries the grounding rules...
  assertStringIncludes(messages[0].content, "ONLY the PRODUCT DATA");
  assertStringIncludes(messages[0].content, "not medical advice");
  // ...and the real data the model may use.
  assertStringIncludes(messages[0].content, "Crunchy Cheese Snacks");
  assertStringIncludes(messages[0].content, "NOVA group 4");
  assertStringIncludes(messages[0].content, "EFSA");
  // The user's question is preserved as its own turn.
  assertEquals(messages[messages.length - 1].role, "user");
  assertStringIncludes(messages[messages.length - 1].content, "safe for my kid");
});

Deno.test("profile allergies/health flags are surfaced for relevance; empty profile is dropped", () => {
  const profile: ChatProfile = {
    allergies: ["milk"],
    healthFlags: ["pregnancy"],
    dietPattern: "vegetarian",
  };
  const withProfile = buildGroundingContext(productRow(), scoreRow(), KB, profile);
  assertEquals(withProfile.profile?.allergies, ["milk"]);

  const empty: ChatProfile = { allergies: [], healthFlags: [], dietPattern: null };
  const dropped = buildGroundingContext(productRow(), scoreRow(), KB, empty);
  assertEquals(dropped.profile, null);
});

// ---------------------------------------------------------------------------
// 2. No-medical-advice + banned-word guardrails
// ---------------------------------------------------------------------------

Deno.test("banned word in the model reply is rejected in favour of a neutral canned reply", async () => {
  const reply = await generateReply(
    buildGroundingContext(productRow(), scoreRow(), KB, null),
    ASK,
    fakeLlm('{"reply":"This product is toxic and dangerous."}').llm,
  );
  assertEquals(reply, CANNED_FILTERED);
});

Deno.test("the disclaimer is ALWAYS present — clean reply, banned reply, and no key", async () => {
  const scenarios: (LlmClient | null)[] = [
    fakeLlm('{"reply":"Contains milk (an allergen) and one moderate-tier additive."}')
      .llm,
    fakeLlm('{"reply":"You definitely have a milk allergy, so this is toxic for you."}')
      .llm,
    null,
  ];
  for (const llm of scenarios) {
    const res = await handleChat(
      chatReq({ productId: PRODUCT_ID, messages: ASK }),
      baseDeps({ llm }),
    );
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.disclaimer, DISCLAIMER);
    assert(typeof body.reply === "string" && body.reply.length > 0);
  }
});

Deno.test("a diagnosis-style reply is safely handled (banned word filtered, disclaimer intact)", async () => {
  // 'toxic' is the fear word the filter catches; the disclaimer covers the rest.
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    baseDeps({
      llm: fakeLlm('{"reply":"You have diabetes so this is toxic for you."}').llm,
    }),
  );
  const body = await res.json();
  assertEquals(body.reply, CANNED_FILTERED);
  assertEquals(body.disclaimer, DISCLAIMER);
});

Deno.test("system prompt forbids outside knowledge and medical advice", () => {
  assertStringIncludes(SYSTEM_PROMPT, "do NOT use outside knowledge");
  assertStringIncludes(SYSTEM_PROMPT, "NOT medical advice");
  assertStringIncludes(SYSTEM_PROMPT, "Never diagnose");
});

// ---------------------------------------------------------------------------
// 3. No fabrication of ungrounded facts
// ---------------------------------------------------------------------------

Deno.test("unknown ingredients contribute NO grounded facts (no fabrication)", () => {
  const row = {
    additivesTags: ["en:e999"], // not in KB
    ingredientsText: "Mystery powder, unicorn extract",
  };
  const facts = resolveIngredientFacts(row, KB);
  assertEquals(facts.length, 0);
});

Deno.test("when the score is missing, the grounded score context is null (not invented)", () => {
  const ctx = buildGroundingContext(productRow(), null, KB, null);
  assertEquals(ctx.score, null);
  const sources = collectSources(ctx);
  // Sources still come from the resolved KB entries, deduped.
  assert(sources.some((s) => s.name.includes("EFSA")));
});

Deno.test("collectSources dedupes and is built from data, never the model", () => {
  const ctx = buildGroundingContext(productRow(), scoreRow(), KB, null);
  const sources = collectSources(ctx);
  const keys = sources.map((s) => `${s.name}|${s.url ?? ""}`);
  assertEquals(new Set(keys).size, keys.length); // no dupes
  assert(sources.some((s) => s.name.includes("NOVA")));
  assert(sources.some((s) => s.name.includes("EFSA")));
});

// ---------------------------------------------------------------------------
// 4. Graceful degradation without an LLM key
// ---------------------------------------------------------------------------

Deno.test("no LLM key → canned unavailable reply, still 200, no throw", async () => {
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    baseDeps({ llm: null }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.reply, CANNED_UNAVAILABLE);
  assertEquals(body.disclaimer, DISCLAIMER);
  assert(Array.isArray(body.sources));
});

Deno.test("LLM error → canned unavailable reply, never throws", async () => {
  const throwing: LlmClient = {
    complete: () => Promise.reject(new Error("boom")),
  };
  const reply = await generateReply(
    buildGroundingContext(productRow(), scoreRow(), KB, null),
    ASK,
    throwing,
  );
  assertEquals(reply, CANNED_UNAVAILABLE);
});

Deno.test("unparsable / wrong-shape model output → canned unavailable", async () => {
  assertEquals(parseReply("not json"), null);
  assertEquals(parseReply('{"nope":"x"}'), null);
  assertEquals(parseReply('{"reply":""}'), null);
  assertEquals(parseReply('{"reply":"  hi  "}'), "hi");

  const reply = await generateReply(
    buildGroundingContext(productRow(), scoreRow(), KB, null),
    ASK,
    fakeLlm("<<garbage>>").llm,
  );
  assertEquals(reply, CANNED_UNAVAILABLE);
});

Deno.test("a failing getProfile never breaks the chat", async () => {
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    baseDeps({ getProfile: () => Promise.reject(new Error("rls")) }),
  );
  assertEquals(res.status, 200);
});

// ---------------------------------------------------------------------------
// 5. Contract, routing & validation
// ---------------------------------------------------------------------------

Deno.test("happy path returns the exact response contract", async () => {
  const { llm, seen } = fakeLlm(
    '{"reply":"It lists milk as an allergen and one moderate-tier additive (E621)."}',
  );
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    baseDeps({ llm }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(Object.keys(body).sort(), ["disclaimer", "reply", "sources"]);
  assertStringIncludes(body.reply, "E621");
  assertEquals(body.disclaimer, DISCLAIMER);
  for (const s of body.sources) {
    assert(typeof s.name === "string");
    assert(s.url === null || typeof s.url === "string");
  }
  // The model was actually given the grounded system prompt.
  assertEquals(seen[0][0].role, "system");
});

Deno.test("product not found → 404", async () => {
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    baseDeps({ getProduct: () => Promise.resolve(null) }),
  );
  assertEquals(res.status, 404);
  assertEquals((await res.json()).error, "not_found");
});

Deno.test("OPTIONS preflight → 204 with CORS", async () => {
  const res = await handleChat(chatReq({}, { method: "OPTIONS" }), baseDeps());
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("non-POST → 405", async () => {
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }, { method: "GET" }),
    baseDeps(),
  );
  assertEquals(res.status, 405);
});

Deno.test("missing Authorization → 401", async () => {
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }, { auth: false }),
    baseDeps(),
  );
  assertEquals(res.status, 401);
});

Deno.test("invalid product id → 400", async () => {
  const res = await handleChat(
    chatReq({ productId: "not-a-uuid", messages: ASK }),
    baseDeps(),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_product_id");
});

Deno.test("empty / user-less message history → 400", async () => {
  const noUser: ChatMessage[] = [{ role: "assistant", content: "hi" }];
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: noUser }),
    baseDeps(),
  );
  assertEquals(res.status, 400);
});

Deno.test("malformed JSON body → 400", async () => {
  const req = new Request("https://x/chat", {
    method: "POST",
    headers: { "Authorization": "Bearer t", "Content-Type": "application/json" },
    body: "{not json",
  });
  const res = await handleChat(req, baseDeps());
  assertEquals(res.status, 400);
});

// ---------------------------------------------------------------------------
// 6. Rate limiting (per-user sliding window)
// ---------------------------------------------------------------------------

Deno.test("withinRateLimit allows under the cap, blocks at/over it", () => {
  const now = 1_000_000;
  const win = 60_000, max = 3;
  assertEquals(withinRateLimit([], now, win, max).allowed, true);
  const three = [now - 100, now - 200, now - 300];
  assertEquals(withinRateLimit(three, now, win, max).allowed, false);
  // Timestamps older than the window don't count.
  assertEquals(
    withinRateLimit([now - 70_000, now - 80_000], now, win, max).allowed,
    true,
  );
});

Deno.test("withinRateLimit retryAfter = window minus age of oldest in-window hit", () => {
  const now = 1_000_000, win = 60_000, max = 2;
  const r = withinRateLimit([now - 10_000, now - 5_000], now, win, max);
  assertEquals(r.allowed, false);
  assertEquals(r.retryAfterSeconds, 50); // oldest hit ages out in 50s
});

/** Deps with the rate-limit hooks wired to a controllable fake ledger. */
function rateDeps(
  opts: { overLimit: boolean; uid?: string | null; now?: number },
): { deps: Deps; state: { recorded: { uid: string; ms: number }[] } } {
  const NOW = opts.now ?? 1_000_000;
  const state = { recorded: [] as { uid: string; ms: number }[] };
  const recent = opts.overLimit
    ? Array.from({ length: RATE_LIMIT_MAX }, (_, i) => NOW - (i + 1) * 100)
    : [];
  const deps = baseDeps({
    now: () => NOW,
    userId: () => (opts.uid === undefined ? "user-1" : opts.uid),
    recentChatRequests: (_uid: string) => Promise.resolve(recent),
    recordChatRequest: (uid: string, ms: number) => {
      state.recorded.push({ uid, ms });
      return Promise.resolve();
    },
  });
  return { deps, state };
}

Deno.test("handleChat returns 429 with calm copy when over the limit", async () => {
  const { deps } = rateDeps({ overLimit: true });
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    deps,
  );
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After") !== null, true);
  const body = await res.json();
  assertEquals(body.error, "rate_limited");
  assertStringIncludes(body.reply, "Give it a minute");
  assertEquals(body.reply, CHAT_RATE_LIMITED);
  assertEquals(body.disclaimer, DISCLAIMER);
});

Deno.test("handleChat records the request and proceeds when under the limit", async () => {
  const { deps, state } = rateDeps({ overLimit: false });
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    deps,
  );
  assertEquals(res.status, 200);
  assertEquals(state.recorded.length, 1); // recordChatRequest called once
});

Deno.test("a 429'd request does NOT record (never extends its own window)", async () => {
  const { deps, state } = rateDeps({ overLimit: true });
  await handleChat(chatReq({ productId: PRODUCT_ID, messages: ASK }), deps);
  assertEquals(state.recorded.length, 0);
});

Deno.test("no userId / missing ledger deps → limiter skipped, behaves as today", async () => {
  // No rate-limit deps at all (baseline deps) → 200, unchanged behaviour.
  const res = await handleChat(
    chatReq({ productId: PRODUCT_ID, messages: ASK }),
    baseDeps(),
  );
  assertEquals(res.status, 200);
});

Deno.test("history is bounded to the last N turns and trimmed", () => {
  const many: ChatMessage[] = [];
  for (let i = 0; i < 20; i++) {
    many.push({ role: i % 2 === 0 ? "user" : "assistant", content: `m${i}` });
  }
  many.push({ role: "user", content: "   " }); // dropped (empty after trim)
  const bounded = boundHistory(many);
  assertEquals(bounded.length, MAX_HISTORY_MESSAGES);
  assertEquals(bounded[bounded.length - 1].content, "m19");
});
