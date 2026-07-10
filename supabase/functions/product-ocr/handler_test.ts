/**
 * POST /product/ocr handler tests — fake deps (no network, no DB).
 */

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import type { ProductRow } from "../product/handler.ts";
import { type Deps, extractIngredientsRegion, handleOcr, parseLabel } from "./handler.ts";

const NOW = Date.parse("2026-07-08T12:00:00Z");

interface FakeState {
  created: Omit<ProductRow, "id">[];
  scores: { productId: string; band: string; score: number | null }[];
}

function makeDeps(): { deps: Deps; state: FakeState } {
  const state: FakeState = { created: [], scores: [] };
  const deps: Deps = {
    createProduct: (row) => {
      state.created.push(row);
      return Promise.resolve({
        ...row,
        id: "33333333-3333-3333-3333-333333333333",
      });
    },
    insertScoreResult: (productId, result) => {
      state.scores.push({ productId, band: result.band, score: result.score });
      return Promise.resolve();
    },
    now: () => NOW,
  };
  return { deps, state };
}

function request(
  body: unknown,
  init: { method?: string; auth?: boolean; raw?: string } = {},
): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (init.auth !== false) headers["Authorization"] = "Bearer test-jwt";
  return new Request("http://localhost/product-ocr", {
    method: init.method ?? "POST",
    headers,
    body: init.raw ?? (body === undefined ? undefined : JSON.stringify(body)),
  });
}

// ---------------------------------------------------------------------------
// Parsing (pure)
// ---------------------------------------------------------------------------

Deno.test("extractIngredientsRegion slices after the header, before nutrition", () => {
  const text =
    "Ingredients: Water, Sugar, Salt, Citric Acid (E330). Nutrition per 100g: ...";
  const region = extractIngredientsRegion(text);
  assertStringIncludes(region, "Water");
  assertStringIncludes(region, "Citric Acid");
  assert(!region.toLowerCase().includes("nutrition"));
});

Deno.test("parseLabel extracts ingredients + additive tags (E-number and by name)", () => {
  const text =
    "INGREDIENTS: Sugar, Palm Oil, Water, Citric Acid (E330), Monosodium Glutamate, colour E102.";
  const parsed = parseLabel(text);
  assertStringIncludes(parsed.ingredients.join("|").toLowerCase(), "sugar");
  assertStringIncludes(parsed.ingredients.join("|").toLowerCase(), "palm oil");
  // E330 via parenthetical, E621 via the name "monosodium glutamate", E102 raw.
  assert(parsed.additivesTags.includes("en:e330"), "E330 from parenthetical");
  assert(parsed.additivesTags.includes("en:e621"), "MSG resolved by name");
  assert(parsed.additivesTags.includes("en:e102"), "E102 raw E-number");
});

Deno.test("parseLabel de-duplicates and drops noise tokens", () => {
  const parsed = parseLabel("Ingredients: Sugar, sugar, 12, , Salt 2%.");
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assertEquals(lower.filter((i) => i === "sugar").length, 1);
  assert(!lower.includes("12"));
  assert(lower.includes("salt"));
});

Deno.test("parseLabel drops the bare additive-class word when its parenthetical is an additive", () => {
  const parsed = parseLabel("Ingredients: Water, Sugar, Colour (E150d), Salt.");
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(!lower.includes("colour"), "no orphan 'colour' display token");
  assert(!lower.includes("color"));
  assert(parsed.additivesTags.includes("en:e150d"), "additive still captured");
  assert(lower.includes("water") && lower.includes("sugar") && lower.includes("salt"));
});

Deno.test("parseLabel keeps a real ingredient that also carries an E-number", () => {
  const parsed = parseLabel("Ingredients: Water, Citric Acid (E330), Salt.");
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(lower.includes("citric acid"), "citric acid is a real ingredient, kept");
  assert(parsed.additivesTags.includes("en:e330"));
});

Deno.test("parseLabel drops class words for named additive parentheticals too", () => {
  const parsed = parseLabel(
    "Ingredients: Cocoa, Emulsifier (Soya Lecithin - E322), Antioxidant (E306).",
  );
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(!lower.includes("emulsifier") && !lower.includes("antioxidant"));
  assert(lower.includes("cocoa"));
  assert(
    parsed.additivesTags.includes("en:e322") && parsed.additivesTags.includes("en:e306"),
  );
});

Deno.test("parseLabel handles a comma inside the additive parenthetical", () => {
  const parsed = parseLabel("Ingredients: Water, Colour (E150c, E150d), Salt.");
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(!lower.includes("colour"), "no orphan 'colour' token despite the comma split");
  assert(!lower.includes("color"));
  // The trailing "E150d)" fragment must not leak in as a stray display token.
  assert(!lower.some((i) => /^e\s?\d{3,4}[a-z]?$/.test(i)), "no stray E-number token");
  assert(lower.includes("water") && lower.includes("salt"));
  // Both colour E-numbers are still captured as additive tags.
  assert(parsed.additivesTags.includes("en:e150c"));
  assert(parsed.additivesTags.includes("en:e150d"));
});

Deno.test("parseLabel reads a Contains allergen statement", () => {
  const parsed = parseLabel(
    "Ingredients: Wheat Flour, Milk, Egg. Contains: wheat, milk and egg.",
  );
  assertEquals(parsed.allergens.map((a) => a.toLowerCase()).sort(), [
    "egg",
    "milk",
    "wheat",
  ]);
});

// ---------------------------------------------------------------------------
// HTTP behaviour
// ---------------------------------------------------------------------------

Deno.test("OPTIONS preflight returns 204 with CORS headers", async () => {
  const { deps } = makeDeps();
  const res = await handleOcr(request(undefined, { method: "OPTIONS" }), deps);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("non-POST → 405", async () => {
  const { deps } = makeDeps();
  const res = await handleOcr(request(undefined, { method: "GET" }), deps);
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

Deno.test("missing Authorization → 401", async () => {
  const { deps, state } = makeDeps();
  const res = await handleOcr(
    request({ text: "Ingredients: Sugar" }, { auth: false }),
    deps,
  );
  assertEquals(res.status, 401);
  assertEquals(state.created.length, 0);
});

Deno.test("invalid JSON body → 400", async () => {
  const { deps } = makeDeps();
  const res = await handleOcr(request(undefined, { raw: "{not json" }), deps);
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_json");
});

Deno.test("empty/too-short text → 400 empty_text", async () => {
  const { deps, state } = makeDeps();
  const res = await handleOcr(request({ text: "  " }), deps);
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "empty_text");
  assertEquals(state.created.length, 0);
});

// ---------------------------------------------------------------------------
// Provisional product creation
// ---------------------------------------------------------------------------

Deno.test("label text → provisional limited product, score omitted (band unknown)", async () => {
  const { deps, state } = makeDeps();
  const text =
    "Ingredients: Sugar, Palm Oil, Cocoa, Emulsifier (Soya Lecithin - E322), Citric Acid (E330).";
  const res = await handleOcr(request({ text, name: "Choco Spread" }), deps);
  assertEquals(res.status, 200);
  const body = await res.json();

  // Persisted as a provisional OCR product.
  assertEquals(state.created.length, 1);
  const row = state.created[0];
  assertEquals(row.source, "ocr");
  assertEquals(row.barcode, null);
  assertEquals(row.data_confidence, "limited");
  assert(row.additives_tags.includes("en:e322"));
  assert(row.additives_tags.includes("en:e330"));
  assertStringIncludes(row.ingredients_text ?? "", "Sugar");
  // "Emulsifier" is an additive-class word whose parenthetical is captured as
  // en:e322 — it must NOT also appear as a redundant display ingredient.
  assert(
    !(row.ingredients_text ?? "").toLowerCase().includes("emulsifier"),
    "no redundant 'Emulsifier' orphan ingredient",
  );

  // Unknown score recorded (OCR has no NOVA / Nutri-Score → limited path).
  assertEquals(state.scores[0].band, "unknown");
  assertEquals(state.scores[0].score, null);

  // Response decodes into Models.swift Product with score omitted.
  assertEquals(body.id, "33333333-3333-3333-3333-333333333333");
  assertEquals(body.name, "Choco Spread");
  assertEquals(body.dataConfidence, "limited");
  assertEquals(body.ingredients, []);
  assertEquals("score" in body, false);
});

Deno.test("default product name when none supplied", async () => {
  const { deps, state } = makeDeps();
  await handleOcr(request({ text: "Ingredients: Water, Salt." }), deps);
  assertEquals(state.created[0].name, "Scanned product");
});

Deno.test("garbage text is handled: still a limited product, no crash", async () => {
  const { deps, state } = makeDeps();
  const res = await handleOcr(request({ text: "@@@ 12 %% ... ???" }), deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.dataConfidence, "limited");
  assertEquals("score" in body, false);
  // No usable ingredient tokens, no invented additives.
  assertEquals(state.created[0].additives_tags, []);
  assertEquals(state.scores[0].band, "unknown");
});
