/**
 * /product/:barcode handler tests — fake deps (no network, no DB).
 */

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { SCORE_VERSION } from "../_shared/scoring/engine.ts";
import type { OffProduct } from "../_shared/off.ts";
import type { UsdaMatch } from "../_shared/usda.ts";
import {
  type Deps,
  extractBarcode,
  handleProduct,
  mapAdditiveTiers,
  type ProductRow,
  type ScoreRow,
} from "./handler.ts";

// ---------------------------------------------------------------------------
// Fixtures + fake deps
// ---------------------------------------------------------------------------

const NOW = Date.parse("2026-07-07T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;

function offProduct(overrides: Partial<OffProduct> = {}): OffProduct {
  return {
    barcode: "3017620422003",
    name: "Nutella",
    brand: "Ferrero",
    novaGroup: 4,
    nutriscoreGrade: "e",
    additivesTags: ["en:e322", "en:e471"],
    allergensTags: ["en:milk", "en:nuts", "en:soybeans"],
    ingredientsText: "Sugar, palm oil, hazelnuts…",
    imageUrl: "https://images.openfoodfacts.org/front.jpg",
    servingSize: "15 g",
    nutriments: { sugars_100g: 56.3 },
    raw: { status: 1 },
    ...overrides,
  };
}

function cachedRow(fetchedAt: string): { product: ProductRow; score: ScoreRow } {
  return {
    product: {
      id: "11111111-1111-1111-1111-111111111111",
      barcode: "3017620422003",
      name: "Nutella",
      brand: "Ferrero",
      source: "off",
      nova_group: 4,
      nutriscore_grade: "e",
      nutrients: {},
      serving_size: "15 g",
      additives_tags: ["en:e322", "en:e471"],
      allergens_tags: ["en:milk", "en:nuts", "en:soybeans"],
      ingredients_text: "Sugar, palm oil…",
      images: { front: "https://images.openfoodfacts.org/front.jpg" },
      data_confidence: "high",
      raw_off: {},
      fetched_at: fetchedAt,
    },
    score: {
      score: 29,
      band: "low",
      confidence: "high",
      breakdown: {
        factors: [
          {
            name: "Processing",
            subScore: 20,
            weight: 0.5,
            detail: "NOVA group 4 (ultra-processed food).",
            sources: [{ name: "NOVA (via Open Food Facts)", url: null }],
          },
        ],
      },
      score_version: SCORE_VERSION,
    },
  };
}

interface FakeState {
  offCalls: string[];
  upserts: Omit<ProductRow, "id">[];
  scoreInserts: { productId: string; band: string; score: number | null }[];
  enrichCalls: { name: string; brand: string | null }[];
}

function makeDeps(opts: {
  cached?: { product: ProductRow; score: ScoreRow | null } | null;
  off?: OffProduct | null | Error;
  enrich?: UsdaMatch | null | Error;
}): { deps: Deps; state: FakeState } {
  const state: FakeState = {
    offCalls: [],
    upserts: [],
    scoreInserts: [],
    enrichCalls: [],
  };
  const deps: Deps = {
    getProductWithScore: () => Promise.resolve(opts.cached ?? null),
    upsertProduct: (row) => {
      state.upserts.push(row);
      return Promise.resolve({
        ...row,
        id: "22222222-2222-2222-2222-222222222222",
      });
    },
    insertScoreResult: (productId, result) => {
      state.scoreInserts.push({
        productId,
        band: result.band,
        score: result.score,
      });
      return Promise.resolve();
    },
    fetchOff: (barcode) => {
      state.offCalls.push(barcode);
      if (opts.off instanceof Error) return Promise.reject(opts.off);
      return Promise.resolve(opts.off ?? null);
    },
    now: () => NOW,
  };
  // Only attach USDA enrichment when the test opts in.
  if ("enrich" in opts) {
    deps.enrichNutrients = (name, brand) => {
      state.enrichCalls.push({ name, brand });
      if (opts.enrich instanceof Error) return Promise.reject(opts.enrich);
      return Promise.resolve(opts.enrich ?? null);
    };
  }
  return { deps, state };
}

function request(
  barcode: string,
  init: { method?: string; auth?: boolean } = {},
): Request {
  const headers: Record<string, string> = {};
  if (init.auth !== false) headers["Authorization"] = "Bearer test-jwt";
  return new Request(`http://localhost/product/${barcode}`, {
    method: init.method ?? "GET",
    headers,
  });
}

// ---------------------------------------------------------------------------
// Routing / validation
// ---------------------------------------------------------------------------

Deno.test("extractBarcode reads the last path segment", () => {
  assertEquals(
    extractBarcode("http://x/functions/v1/product/3017620422003"),
    "3017620422003",
  );
  assertEquals(extractBarcode("http://x/product/123456"), "123456");
  assertEquals(extractBarcode("http://x/product/"), null);
  assertEquals(extractBarcode("http://x/product"), null);
});

Deno.test("OPTIONS preflight returns 204 with CORS headers", async () => {
  const { deps } = makeDeps({});
  const res = await handleProduct(request("123456", { method: "OPTIONS" }), deps);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("missing Authorization header → 401", async () => {
  const { deps, state } = makeDeps({});
  const res = await handleProduct(request("3017620422003", { auth: false }), deps);
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(state.offCalls.length, 0);
});

Deno.test("invalid barcodes → 400", async () => {
  const { deps } = makeDeps({});
  for (const bad of ["12345", "123456789012345", "12345abc", "abc"]) {
    const res = await handleProduct(request(bad), deps);
    assertEquals(res.status, 400, `barcode "${bad}" should be rejected`);
    assertEquals((await res.json()).error, "invalid_barcode");
  }
});

Deno.test("non-GET method → 405", async () => {
  const { deps } = makeDeps({});
  const res = await handleProduct(request("3017620422003", { method: "POST" }), deps);
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

// ---------------------------------------------------------------------------
// Cache behavior
// ---------------------------------------------------------------------------

Deno.test("fresh cache hit returns cached product without calling OFF", async () => {
  const fetchedAt = new Date(NOW - 5 * DAY_MS).toISOString();
  const { deps, state } = makeDeps({ cached: cachedRow(fetchedAt) });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  const body = await res.json();

  assertEquals(state.offCalls.length, 0, "must not touch OFF on a fresh hit");
  assertEquals(state.upserts.length, 0);
  assertEquals(body.id, "11111111-1111-1111-1111-111111111111");
  assertEquals(body.score.score, 29);
  assertEquals(body.score.band, "low");
  assertEquals(body.score.scoreVersion, SCORE_VERSION);
});

Deno.test("stale cache (older than 30 days) refetches and rescores", async () => {
  const fetchedAt = new Date(NOW - 45 * DAY_MS).toISOString();
  const { deps, state } = makeDeps({
    cached: cachedRow(fetchedAt),
    off: offProduct(),
  });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  await res.body?.cancel();

  assertEquals(state.offCalls, ["3017620422003"]);
  assertEquals(state.upserts.length, 1);
  assertEquals(state.scoreInserts.length, 1);
});

Deno.test("cached row with outdated score_version recomputes", async () => {
  const row = cachedRow(new Date(NOW - 1 * DAY_MS).toISOString());
  row.score.score_version = "0.9.0";
  const { deps, state } = makeDeps({ cached: row, off: offProduct() });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(state.offCalls.length, 1, "stale version must trigger refetch");
  assertEquals(state.scoreInserts[0].band, "low");
});

// ---------------------------------------------------------------------------
// Cache miss → fetch → score
// ---------------------------------------------------------------------------

Deno.test("cache miss fetches OFF, scores, persists, and returns the Swift shape", async () => {
  const { deps, state } = makeDeps({ cached: null, off: offProduct() });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Type"), "application/json");
  const body = await res.json();

  // Persisted via service role.
  assertEquals(state.upserts.length, 1);
  assertEquals(state.upserts[0].source, "off");
  assertEquals(state.scoreInserts.length, 1);
  assertEquals(
    state.scoreInserts[0].productId,
    "22222222-2222-2222-2222-222222222222",
  );

  // Response decodes into Models.swift Product.
  assertEquals(body.id, "22222222-2222-2222-2222-222222222222");
  assertEquals(body.barcode, "3017620422003");
  assertEquals(body.name, "Nutella");
  assertEquals(body.brand, "Ferrero");
  assertEquals(body.imageURL, "https://images.openfoodfacts.org/front.jpg");
  assertEquals(body.ingredients, []);
  assertEquals(body.allergens, ["milk", "nuts", "soybeans"]); // prefix stripped
  assertEquals(body.dataConfidence, "high");

  // NOVA 4 + Nutri-Score E + 2 low-tier additives (e322, e471):
  // 0.5×20 + 0.35×12 + 0.15×100 = 29.2 → 29 → "low"
  assertEquals(body.score.score, 29);
  assertEquals(body.score.band, "low");
  assertEquals(body.score.confidence, "high");
  assertEquals(body.score.scoreVersion, SCORE_VERSION);
  assertEquals(body.score.factors.length, 3);
  assertEquals(
    body.score.factors.map((f: { name: string }) => f.name),
    ["Processing", "Nutrition", "Additives"],
  );
  for (const f of body.score.factors) {
    assertEquals(typeof f.subScore, "number");
    assertEquals(typeof f.weight, "number");
    assertEquals(typeof f.detail, "string");
    assertEquals(Array.isArray(f.sources), true);
  }
});

Deno.test("product with no NOVA and no Nutri-Score → score object omitted", async () => {
  const { deps, state } = makeDeps({
    cached: null,
    off: offProduct({ novaGroup: null, nutriscoreGrade: null }),
  });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  const body = await res.json();

  // Swift's ScoreResult.score is non-optional — the whole object is omitted.
  assertEquals("score" in body, false);
  assertEquals(body.dataConfidence, "limited");
  // The unknown result is still recorded for the cache.
  assertEquals(state.scoreInserts[0].band, "unknown");
  assertEquals(state.scoreInserts[0].score, null);
});

Deno.test("OFF not found → 404 with needsOcr", async () => {
  const { deps, state } = makeDeps({ cached: null, off: null });
  const res = await handleProduct(request("4009900484602"), deps);
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.error, "not_found");
  assertEquals(body.needsOcr, true);
  assertEquals(state.upserts.length, 0, "nothing to persist when not found");
});

Deno.test("OFF failure → 502 upstream_error", async () => {
  const { deps } = makeDeps({ cached: null, off: new Error("HTTP 500") });
  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error, "upstream_error");
});

// ---------------------------------------------------------------------------
// Additive tier mapping
// ---------------------------------------------------------------------------

Deno.test("mapAdditiveTiers maps curated additives to their tiers", () => {
  const { tiers, unknown } = mapAdditiveTiers([
    "en:e330", // citric acid → low
    "en:e621", // MSG → moderate
    "en:e250", // sodium nitrite → higher
  ]);
  assertEquals(tiers, ["low", "moderate", "higher"]);
  assertEquals(unknown, []);
});

Deno.test("unreviewed additives score as low and are flagged, never invented", async () => {
  const { tiers, unknown } = mapAdditiveTiers(["en:e330", "en:e9999"]);
  assertEquals(tiers, ["low", "low"]);
  assertEquals(unknown, ["E9999"]);

  const { deps } = makeDeps({
    cached: null,
    off: offProduct({ additivesTags: ["en:e330", "en:e9999"] }),
  });
  const res = await handleProduct(request("3017620422003"), deps);
  const body = await res.json();
  const additives = body.score.factors.find(
    (f: { name: string }) => f.name === "Additives",
  );
  assertEquals(additives.subScore, 100, "unreviewed must not add penalties");
  assertStringIncludes(additives.detail, "not yet in our review table");
  assertStringIncludes(additives.detail, "E9999");
});

// ---------------------------------------------------------------------------
// USDA nutrient enrichment (miss path only, OFF precedence, best-effort)
// ---------------------------------------------------------------------------

const USDA_MATCH: UsdaMatch = {
  fdcId: 12345,
  description: "Hazelnut spread",
  dataType: "Branded",
  nutrients: {
    "energy-kcal_100g": 539,
    fat_100g: 30.9,
    proteins_100g: 99, // must be ignored — OFF has none here, so it fills
    sugars_100g: 12, // OFF already has 56.3 → OFF wins
  },
};

Deno.test("enrichment: thin OFF nutrients are filled from USDA (OFF precedence)", async () => {
  // OFF here has only sugars_100g (thin).
  const { deps, state } = makeDeps({
    cached: null,
    off: offProduct({ nutriments: { sugars_100g: 56.3 } }),
    enrich: USDA_MATCH,
  });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  await res.body?.cancel();

  assertEquals(state.enrichCalls, [{ name: "Nutella", brand: "Ferrero" }]);
  const stored = state.upserts[0].nutrients as Record<string, unknown>;
  assertEquals(stored["sugars_100g"], 56.3, "OFF sugars preserved");
  assertEquals(stored["energy-kcal_100g"], 539, "USDA fills energy");
  assertEquals(stored["fat_100g"], 30.9, "USDA fills fat");
  assertEquals(stored["proteins_100g"], 99, "USDA fills a genuine gap");
  const prov = stored["_enrichment"] as Record<string, unknown>;
  assertEquals(prov.source, "usda");
  assertEquals(prov.fdcId, 12345);
  assertEquals(
    (prov.fields as string[]).sort(),
    ["energy-kcal_100g", "fat_100g", "proteins_100g"],
  );
});

Deno.test("enrichment: a full OFF nutrient table is NOT enriched", async () => {
  const full = {
    "energy-kcal_100g": 539,
    sugars_100g: 56.3,
    fat_100g: 30.9,
    "saturated-fat_100g": 10.6,
    proteins_100g: 6.3,
    salt_100g: 0.107,
  };
  const { deps, state } = makeDeps({
    cached: null,
    off: offProduct({ nutriments: full }),
    enrich: USDA_MATCH,
  });

  const res = await handleProduct(request("3017620422003"), deps);
  await res.body?.cancel();

  assertEquals(state.enrichCalls.length, 0, "full data → no USDA call");
  const stored = state.upserts[0].nutrients as Record<string, unknown>;
  assertEquals("_enrichment" in stored, false);
});

Deno.test("enrichment: never runs on a fresh cache hit", async () => {
  const fetchedAt = new Date(NOW - 5 * DAY_MS).toISOString();
  const { deps, state } = makeDeps({
    cached: cachedRow(fetchedAt),
    enrich: USDA_MATCH,
  });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(state.offCalls.length, 0);
  assertEquals(state.enrichCalls.length, 0, "cache hit must not touch USDA");
});

Deno.test("enrichment: a USDA error never breaks the scan (OFF nutrients kept)", async () => {
  const { deps, state } = makeDeps({
    cached: null,
    off: offProduct({ nutriments: { sugars_100g: 56.3 } }),
    enrich: new Error("USDA down"),
  });

  const res = await handleProduct(request("3017620422003"), deps);
  assertEquals(res.status, 200, "scan still succeeds on OFF alone");
  await res.body?.cancel();
  const stored = state.upserts[0].nutrients as Record<string, unknown>;
  assertEquals(stored, { sugars_100g: 56.3 }, "OFF nutrients unchanged");
});

Deno.test("enrichment: no USDA match leaves OFF nutrients unchanged", async () => {
  const { deps, state } = makeDeps({
    cached: null,
    off: offProduct({ nutriments: { sugars_100g: 56.3 } }),
    enrich: null,
  });

  const res = await handleProduct(request("3017620422003"), deps);
  await res.body?.cancel();
  assertEquals(state.enrichCalls.length, 1);
  const stored = state.upserts[0].nutrients as Record<string, unknown>;
  assertEquals(stored, { sugars_100g: 56.3 });
});
