/**
 * GET /search?q= handler tests — fake deps (no network, no DB).
 * Mirrors product/handler_test.ts's injected-Deps style.
 */

import { assertEquals } from "jsr:@std/assert@1";
import { SCORE_VERSION } from "../_shared/scoring/engine.ts";
import type { OffProduct } from "../_shared/off.ts";
import { type Deps, extractQuery, handleSearch, type ScoreEntry } from "./handler.ts";

// ---------------------------------------------------------------------------
// Fixtures + fake deps
// ---------------------------------------------------------------------------

function offProduct(overrides: Partial<OffProduct> = {}): OffProduct {
  return {
    barcode: "3017620422003",
    name: "Nutella",
    brand: "Ferrero",
    novaGroup: 4,
    nutriscoreGrade: "e",
    additivesTags: [],
    allergensTags: [],
    categoriesTags: [],
    ingredientsText: null,
    imageUrl: "https://images.openfoodfacts.org/front.jpg",
    servingSize: null,
    nutriments: {},
    raw: {},
    ...overrides,
  };
}

interface FakeState {
  searchCalls: string[];
  scoreLookups: string[][];
}

function makeDeps(opts: {
  off?: OffProduct[] | Error;
  scores?: Map<string, ScoreEntry>;
}): { deps: Deps; state: FakeState } {
  const state: FakeState = { searchCalls: [], scoreLookups: [] };
  const deps: Deps = {
    searchOff: (query) => {
      state.searchCalls.push(query);
      if (opts.off instanceof Error) return Promise.reject(opts.off);
      return Promise.resolve(opts.off ?? []);
    },
    getScoresForBarcodes: (barcodes) => {
      state.scoreLookups.push(barcodes);
      return Promise.resolve(opts.scores ?? new Map());
    },
  };
  return { deps, state };
}

function request(
  q: string | null,
  init: { method?: string; auth?: boolean } = {},
): Request {
  const headers: Record<string, string> = {};
  if (init.auth !== false) headers["Authorization"] = "Bearer test-jwt";
  const url = q === null
    ? "http://localhost/search"
    : `http://localhost/search?q=${encodeURIComponent(q)}`;
  return new Request(url, { method: init.method ?? "GET", headers });
}

// ---------------------------------------------------------------------------
// Routing / validation
// ---------------------------------------------------------------------------

Deno.test("extractQuery trims and reads ?q=", () => {
  assertEquals(extractQuery("http://x/search?q=nutella"), "nutella");
  assertEquals(extractQuery("http://x/search?q=%20%20oats%20"), "oats");
  assertEquals(extractQuery("http://x/search"), "");
  assertEquals(extractQuery("http://x/search?q="), "");
});

Deno.test("OPTIONS preflight returns 204 with CORS headers", async () => {
  const { deps } = makeDeps({});
  const res = await handleSearch(request("nutella", { method: "OPTIONS" }), deps);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("non-GET method → 405", async () => {
  const { deps } = makeDeps({});
  const res = await handleSearch(request("nutella", { method: "POST" }), deps);
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

Deno.test("missing Authorization header → 401", async () => {
  const { deps, state } = makeDeps({});
  const res = await handleSearch(request("nutella", { auth: false }), deps);
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(state.searchCalls.length, 0);
});

Deno.test("empty / whitespace q → 400 empty_query", async () => {
  const { deps, state } = makeDeps({});
  for (const q of ["", "   ", null]) {
    const res = await handleSearch(request(q), deps);
    assertEquals(res.status, 400, `q=${JSON.stringify(q)} should be rejected`);
    assertEquals((await res.json()).error, "empty_query");
  }
  assertEquals(state.searchCalls.length, 0, "never hits OFF for an empty query");
});

// ---------------------------------------------------------------------------
// Happy path + score attachment
// ---------------------------------------------------------------------------

Deno.test("happy path: attaches OUR score only for barcodes we've scored", async () => {
  const scores = new Map<string, ScoreEntry>([
    ["3017620422003", { score: 29, band: "low", score_version: SCORE_VERSION }],
  ]);
  const { deps, state } = makeDeps({
    off: [
      offProduct({ barcode: "3017620422003", name: "Nutella" }),
      offProduct({ barcode: "0000000000001", name: "Store Oats", brand: null, imageUrl: null }),
    ],
    scores,
  });

  const res = await handleSearch(request("nutella"), deps);
  assertEquals(res.status, 200);
  const body = await res.json();

  assertEquals(state.searchCalls, ["nutella"]);
  assertEquals(state.scoreLookups[0].sort(), ["0000000000001", "3017620422003"]);
  assertEquals(body.results.length, 2);

  const a = body.results.find((r: { barcode: string }) => r.barcode === "3017620422003");
  assertEquals(a.name, "Nutella");
  assertEquals(a.brand, "Ferrero");
  assertEquals(a.imageURL, "https://images.openfoodfacts.org/front.jpg");
  assertEquals(a.score, { score: 29, band: "low" });

  const b = body.results.find((r: { barcode: string }) => r.barcode === "0000000000001");
  assertEquals(b.name, "Store Oats");
  assertEquals(b.brand, null);
  assertEquals(b.imageURL, null);
  assertEquals("score" in b, false, "unscored row omits score entirely");
});

Deno.test("score attached ONLY at the current SCORE_VERSION (stale version omitted)", async () => {
  const scores = new Map<string, ScoreEntry>([
    ["3017620422003", { score: 29, band: "low", score_version: "0.9.0" }],
  ]);
  const { deps } = makeDeps({ off: [offProduct()], scores });

  const res = await handleSearch(request("nutella"), deps);
  const body = await res.json();
  assertEquals("score" in body.results[0], false, "stale-version score is not shown as ours");
});

Deno.test("an unknown-band cached score is never surfaced", async () => {
  const scores = new Map<string, ScoreEntry>([
    ["3017620422003", { score: 0, band: "unknown", score_version: SCORE_VERSION }],
  ]);
  const { deps } = makeDeps({ off: [offProduct()], scores });

  const res = await handleSearch(request("nutella"), deps);
  const body = await res.json();
  assertEquals("score" in body.results[0], false, "unknown band → neutral affordance");
});

Deno.test("rows with a blank name (Unknown product) or blank barcode are dropped", async () => {
  const { deps } = makeDeps({
    off: [
      offProduct({ barcode: "3017620422003", name: "Nutella" }),
      offProduct({ barcode: "0000000000002", name: "Unknown product" }),
      offProduct({ barcode: "", name: "No barcode" }),
    ],
  });
  const res = await handleSearch(request("nutella"), deps);
  const body = await res.json();
  assertEquals(body.results.length, 1);
  assertEquals(body.results[0].barcode, "3017620422003");
});

Deno.test("empty OFF result → 200 with empty results array", async () => {
  const { deps, state } = makeDeps({ off: [] });
  const res = await handleSearch(request("zzzznomatch"), deps);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.results, []);
  assertEquals(state.scoreLookups.length, 0, "no barcodes → no score lookup");
});

Deno.test("OFF throws → 502 upstream_error", async () => {
  const { deps } = makeDeps({ off: new Error("OFF down") });
  const res = await handleSearch(request("nutella"), deps);
  assertEquals(res.status, 502);
  assertEquals((await res.json()).error, "upstream_error");
});

Deno.test("q longer than 100 chars is truncated before hitting OFF", async () => {
  const { deps, state } = makeDeps({ off: [] });
  const longQuery = "a".repeat(250);
  const res = await handleSearch(request(longQuery), deps);
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(state.searchCalls[0].length, 100);
});
