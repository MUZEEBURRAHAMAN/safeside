/**
 * GET /product/:id/ingredients handler tests — fake deps (no network, no DB).
 * The LLM is mocked; guardrail internals are covered in _shared/kb/kb_test.ts.
 */

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { LlmClient } from "../_shared/llm.ts";
import { type IngredientOut, KB_VERSION, type KbEntry } from "../_shared/kb/kb.ts";
import {
  buildCandidates,
  type Deps,
  extractProductId,
  handleIngredients,
  parseIngredientTokens,
  type ProductIngredientsRow,
} from "./handler.ts";

const PRODUCT_ID = "22222222-2222-2222-2222-222222222222";

function entry(overrides: Partial<KbEntry>): KbEntry {
  return {
    id: "en:sugar",
    names: ["Sugar", "Sucrose"],
    what: "Sugar that adds sweetness.",
    why_used: "Adds sweetness and bulk.",
    safety: "WHO suggests limiting free sugars.",
    risk_tier: "low",
    who_should_avoid: [],
    misconceptions: [],
    found_in: ["sweets"],
    sources: [{ name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov/" }],
    confidence: "high",
    last_reviewed: "2026-07",
    kb_version: KB_VERSION,
    ...overrides,
  };
}

const KB: KbEntry[] = [
  entry({ id: "en:sugar", names: ["Sugar", "Sucrose"] }),
  entry({
    id: "en:e621",
    names: ["Monosodium glutamate", "MSG", "E621"],
    what: "A flavour enhancer.",
    risk_tier: "moderate",
  }),
  entry({
    id: "en:e150d",
    names: ["Sulphite ammonia caramel", "E150d"],
    what: "A caramel colour.",
    why_used: "Adds a brown colour.",
    safety: "EFSA set a group ADI for caramel colours.",
    risk_tier: "moderate",
  }),
  entry({
    id: "en:e338",
    names: ["Phosphoric acid", "E338"],
    what: "A phosphate additive.",
    why_used: "Regulates acidity.",
    safety: "EFSA set a group intake limit for phosphates.",
    risk_tier: "moderate",
  }),
];

interface FakeState {
  llmCalls: number;
  saved: string[];
  cache: Map<string, IngredientOut>;
}

function cacheKey(id: string, v: string, l: string) {
  return `${id}|${v}|${l}`;
}

function makeDeps(opts: {
  product?: ProductIngredientsRow | null;
  llm?: LlmClient | null;
  preCached?: { id: string; explanation: IngredientOut }[];
}): { deps: Deps; state: FakeState } {
  const state: FakeState = { llmCalls: 0, saved: [], cache: new Map() };
  for (const p of opts.preCached ?? []) {
    state.cache.set(cacheKey(p.id, KB_VERSION, "en"), p.explanation);
  }
  const defaultLlm: LlmClient = {
    complete: () => {
      state.llmCalls++;
      return Promise.resolve(
        JSON.stringify({ what: "rewritten", whyUsed: "", safety: "" }),
      );
    },
  };
  const deps: Deps = {
    getProduct: () =>
      Promise.resolve(
        opts.product === undefined
          ? {
            additivesTags: [],
            ingredientsText: null,
          }
          : opts.product,
      ),
    getKb: () => Promise.resolve(KB),
    getCached: (id, v, l) => Promise.resolve(state.cache.get(cacheKey(id, v, l)) ?? null),
    saveCached: (id, v, l, expl) => {
      state.saved.push(id);
      state.cache.set(cacheKey(id, v, l), expl);
      return Promise.resolve();
    },
    llm: opts.llm === undefined ? defaultLlm : opts.llm,
    now: () => 0,
  };
  return { deps, state };
}

function request(path: string, init: { method?: string; auth?: boolean } = {}): Request {
  const headers: Record<string, string> = {};
  if (init.auth !== false) headers["Authorization"] = "Bearer test-jwt";
  return new Request(`http://localhost${path}`, {
    method: init.method ?? "GET",
    headers,
  });
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

Deno.test("extractProductId handles both path shapes and a query fallback", () => {
  assertEquals(extractProductId(`http://x/ingredients/${PRODUCT_ID}`), PRODUCT_ID);
  assertEquals(
    extractProductId(`http://x/functions/v1/product/${PRODUCT_ID}/ingredients`),
    PRODUCT_ID,
  );
  assertEquals(extractProductId(`http://x/ingredients?id=${PRODUCT_ID}`), PRODUCT_ID);
  assertEquals(extractProductId("http://x/ingredients"), null);
});

Deno.test("parseIngredientTokens cleans a comma list", () => {
  assertEquals(
    parseIngredientTokens("Sugar, Palm Oil (30%), Cocoa; Emulsifier (E322)"),
    ["Sugar", "Palm Oil", "Cocoa", "Emulsifier"],
  );
  assertEquals(parseIngredientTokens(null), []);
});

Deno.test("buildCandidates resolves by id + synonym and preserves order", () => {
  const cands = buildCandidates(
    { additivesTags: ["en:e621"], ingredientsText: "Sugar, Mystery Fiber" },
    KB,
  );
  assertEquals(cands.map((c) => c.display), [
    "Sugar",
    "Mystery Fiber",
    "Monosodium glutamate",
  ]);
  assertEquals(cands[0].entry?.id, "en:sugar");
  assertEquals(cands[1].entry, null); // unknown
  assertEquals(cands[2].entry?.id, "en:e621");
});

Deno.test("buildCandidates surfaces additives absent from the text (the Coca-Cola case)", () => {
  // E150d + E338 appear ONLY in additives_tags (the label hides them inside
  // "colour (E150d)" etc., which the token parser strips).
  const cands = buildCandidates(
    {
      additivesTags: ["en:e150d", "en:e338"],
      ingredientsText: "Carbonated water, Sugar",
    },
    KB,
  );
  assertEquals(cands.map((c) => c.display), [
    "Carbonated water", // unknown text token, kept in label order
    "Sugar",
    "Sulphite ammonia caramel", // en:e150d, appended from additives_tags
    "Phosphoric acid", // en:e338, appended from additives_tags
  ]);
  assertEquals(cands[2].entry?.id, "en:e150d");
  assertEquals(cands[3].entry?.id, "en:e338");
});

Deno.test("buildCandidates de-dupes an additive named in both text and additives_tags", () => {
  // "Phosphoric acid" is a synonym of en:e338 AND listed in additives_tags.
  const cands = buildCandidates(
    { additivesTags: ["en:e338"], ingredientsText: "Sugar, Phosphoric acid" },
    KB,
  );
  assertEquals(cands.map((c) => c.display), ["Sugar", "Phosphoric acid"]);
  assertEquals(cands.filter((c) => c.entry?.id === "en:e338").length, 1);
});

Deno.test("buildCandidates tolerates an additive tag without the en: prefix", () => {
  const cands = buildCandidates({ additivesTags: ["e338"], ingredientsText: null }, KB);
  assertEquals(cands.length, 1);
  assertEquals(cands[0].display, "Phosphoric acid");
  assertEquals(cands[0].entry?.id, "en:e338");
});

// ---------------------------------------------------------------------------
// HTTP behaviour
// ---------------------------------------------------------------------------

Deno.test("OPTIONS → 204; non-GET → 405; missing auth → 401", async () => {
  const { deps } = makeDeps({});
  assertEquals(
    (await handleIngredients(request("/ingredients/x", { method: "OPTIONS" }), deps))
      .status,
    204,
  );
  const m = await handleIngredients(
    request(`/ingredients/${PRODUCT_ID}`, { method: "POST" }),
    deps,
  );
  assertEquals(m.status, 405);
  await m.body?.cancel();
  const u = await handleIngredients(
    request(`/ingredients/${PRODUCT_ID}`, { auth: false }),
    deps,
  );
  assertEquals(u.status, 401);
});

Deno.test("non-UUID product id → 400", async () => {
  const { deps } = makeDeps({});
  const res = await handleIngredients(request("/ingredients/not-a-uuid"), deps);
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_product_id");
});

Deno.test("unknown product → 404", async () => {
  const { deps } = makeDeps({ product: null });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  assertEquals(res.status, 404);
});

// ---------------------------------------------------------------------------
// The feature
// ---------------------------------------------------------------------------

Deno.test("KB hit rewrites + caches; KB miss returns limited without the LLM", async () => {
  const { deps, state } = makeDeps({
    product: {
      additivesTags: ["en:e621", "en:e999"],
      ingredientsText: "Sugar, Weirdium",
    },
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  assertEquals(res.status, 200);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };

  // Sugar + MSG (KB hits) rewritten & cached; Weirdium + E999 (misses) limited.
  const byName = Object.fromEntries(ingredients.map((i) => [i.name, i]));
  assertEquals(byName["Sugar"].what, "rewritten");
  assertEquals(byName["Sugar"].riskTier, "low");
  assertEquals(byName["Monosodium glutamate"].riskTier, "moderate");

  const weirdium = ingredients.find((i) => i.name === "Weirdium")!;
  assertEquals(weirdium.confidence, "limited");
  assert(weirdium.what?.includes("don't have vetted info"));
  const e999 = ingredients.find((i) => i.name === "E999")!;
  assertEquals(e999.confidence, "limited");

  // The LLM ran only for the two KB hits; both were cached.
  assertEquals(state.llmCalls, 2);
  assertEquals(state.saved.sort(), ["en:e621", "en:sugar"]);
});

Deno.test("cache hit is served without calling the LLM", async () => {
  const cached: IngredientOut = {
    name: "Sugar",
    what: "cached what",
    whyUsed: null,
    safety: null,
    riskTier: "low",
    whoShouldAvoid: [],
    misconceptions: [],
    foundIn: [],
    sources: [],
    confidence: "high",
  };
  const { deps, state } = makeDeps({
    product: { additivesTags: [], ingredientsText: "Sugar" },
    preCached: [{ id: "en:sugar", explanation: cached }],
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };
  assertEquals(ingredients[0].what, "cached what");
  assertEquals(state.llmCalls, 0, "cache hit must not call the LLM");
  assertEquals(state.saved.length, 0);
});

Deno.test("missing LLM key → raw KB fields, still no fabrication", async () => {
  const { deps, state } = makeDeps({
    product: { additivesTags: [], ingredientsText: "Sugar" },
    llm: null,
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };
  assertEquals(state.llmCalls, 0);
  assertEquals(ingredients[0].what, "Sugar that adds sweetness."); // raw KB verbatim
  assertEquals(ingredients[0].riskTier, "low");
  // Even with no LLM, the explanation is cached for reuse.
  assertEquals(state.saved, ["en:sugar"]);
});

Deno.test("additives_tags [en:e150d, en:e338] get KB-sourced explanations for BOTH", async () => {
  // The exact live regression: a cola whose E-numbers live only in
  // additives_tags (not spelled out in the text) must still be explained.
  const { deps, state } = makeDeps({
    product: {
      additivesTags: ["en:e150d", "en:e338"],
      ingredientsText: "Carbonated water, Sugar",
    },
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  assertEquals(res.status, 200);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };
  const byName = Object.fromEntries(ingredients.map((i) => [i.name, i]));

  // Both additives resolved to full, sourced, KB-backed explanations.
  for (const name of ["Sulphite ammonia caramel", "Phosphoric acid"]) {
    assert(byName[name], `${name} should surface from additives_tags`);
    assertEquals(byName[name].what, "rewritten"); // went through the LLM path
    assertEquals(byName[name].confidence, "high");
    // riskTier is copied verbatim from the KB — the LLM can't change it.
    assertEquals(byName[name].riskTier, "moderate");
  }

  // Carbonated water is unknown; Sugar + both additives are the 3 KB hits.
  assertEquals(byName["Carbonated water"].confidence, "limited");
  assertEquals(state.llmCalls, 3);
  assertEquals(state.saved.sort(), ["en:e150d", "en:e338", "en:sugar"]);
});

Deno.test("an additive in both the text and additives_tags is explained once", async () => {
  const { deps } = makeDeps({
    product: { additivesTags: ["en:e338"], ingredientsText: "Sugar, Phosphoric acid" },
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };
  const e338 = ingredients.filter((i) => i.name === "Phosphoric acid");
  assertEquals(e338.length, 1, "E338 must not be listed twice");
  assertEquals(e338[0].riskTier, "moderate");
});

Deno.test("additive rows carry an INS-class category; plain food tokens carry null", async () => {
  const { deps } = makeDeps({
    product: {
      additivesTags: ["en:e621"], // flavour enhancer
      ingredientsText: "Sugar, Weirdium",
    },
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };
  const byName = Object.fromEntries(ingredients.map((i) => [i.name, i]));

  assertEquals(byName["Monosodium glutamate"].category, "Flavour enhancers");
  assertEquals(byName["Sugar"].category, null); // plain food token → no pill
  assertEquals(byName["Weirdium"].category, null); // unknown, non-additive → no pill
});

Deno.test("an additive tag with no KB entry → limited state, never the LLM", async () => {
  const { deps, state } = makeDeps({
    product: { additivesTags: ["en:e999"], ingredientsText: null },
  });
  const res = await handleIngredients(request(`/ingredients/${PRODUCT_ID}`), deps);
  const { ingredients } = await res.json() as { ingredients: IngredientOut[] };
  assertEquals(ingredients.length, 1);
  assertEquals(ingredients[0].name, "E999");
  assertEquals(ingredients[0].confidence, "limited");
  assert(ingredients[0].what?.includes("don't have vetted info"));
  assertEquals(ingredients[0].riskTier, null);
  assertEquals(state.llmCalls, 0, "never call the LLM for an unknown additive");
});
