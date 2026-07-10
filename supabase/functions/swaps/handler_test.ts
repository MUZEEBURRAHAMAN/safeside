/**
 * Swaps ranking + why-better tests — pure, offline. No network/DB: every Dep
 * is a fake. Mirrors product/handler_test.ts fixture style.
 *
 * The ranking and every "why better" fact are deterministic diffs of stored DB
 * fields (CLAUDE.md #5 — the LLM never runs here), so these assertions pin the
 * exact behaviour the iOS sheet renders.
 */

import { assertEquals } from "jsr:@std/assert@1";
import {
  type Deps,
  extractSubjectId,
  handleSwaps,
  rankSwaps,
  type SwapProductRow,
  whyBetter,
} from "./handler.ts";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const SUBJECT_ID = "11111111-1111-1111-1111-111111111111";
const AUTH = { Authorization: "Bearer test-jwt" };

function row(overrides: Partial<SwapProductRow> = {}): SwapProductRow {
  return {
    id: crypto.randomUUID(),
    barcode: "9990000000000",
    name: "Product",
    brand: null,
    imageURL: null,
    categoriesTags: ["en:chocolate-spreads"],
    additivesTags: [],
    allergensTags: [],
    nutrients: {},
    score: 60,
    band: "mid",
    ...overrides,
  };
}

/** A low-scoring subject: NOVA-4 spread with a moderate colour + high sat fat. */
function subjectRow(overrides: Partial<SwapProductRow> = {}): SwapProductRow {
  return row({
    id: SUBJECT_ID,
    name: "Choco Spread",
    score: 29,
    band: "low",
    additivesTags: ["en:e150d", "en:e330"], // e150d moderate (colour), e330 low
    allergensTags: ["en:milk"],
    nutrients: { "saturated-fat_100g": 10.6, sugars_100g: 56, salt_100g: 0.1 },
    ...overrides,
  });
}

function makeDeps(opts: {
  subject?: SwapProductRow | null;
  candidates?: SwapProductRow[];
  pantry?: Set<string>;
  allergies?: string[];
}): Deps {
  return {
    getSubject: () =>
      Promise.resolve(opts.subject === undefined ? subjectRow() : opts.subject),
    getCandidates: () => Promise.resolve(opts.candidates ?? []),
    getPantryProductIds: () => Promise.resolve(opts.pantry ?? new Set<string>()),
    getAllergies: () => Promise.resolve(opts.allergies ?? []),
    now: () => 0,
  };
}

function get(id: string, headers: Record<string, string> = AUTH): Request {
  return new Request(`https://x/functions/v1/swaps/product/${id}/swaps`, {
    method: "GET",
    headers,
  });
}

async function body(res: Response): Promise<Record<string, unknown>> {
  return await res.json() as Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// 1. extractSubjectId
// ---------------------------------------------------------------------------

Deno.test("extractSubjectId parses the id from the swaps path (both prefixes)", () => {
  assertEquals(
    extractSubjectId(`https://x/functions/v1/swaps/product/${SUBJECT_ID}/swaps`),
    SUBJECT_ID,
  );
  assertEquals(
    extractSubjectId(`https://x/swaps/product/${SUBJECT_ID}/swaps`),
    SUBJECT_ID,
  );
});

// ---------------------------------------------------------------------------
// 2. Happy path — higher-scored same-category candidate with why-better
// ---------------------------------------------------------------------------

Deno.test("returns a higher same-category candidate with correct delta + why-better", async () => {
  const better = row({
    id: "22222222-2222-2222-2222-222222222222",
    name: "Cleaner Spread",
    score: 71,
    band: "mid",
    additivesTags: ["en:e330"], // dropped the e150d colour
    // sugars unchanged (56) so only saturated fat qualifies as "lower".
    nutrients: { "saturated-fat_100g": 3.0, sugars_100g: 56, salt_100g: 0.1 },
  });
  const res = await handleSwaps(get(SUBJECT_ID), makeDeps({ candidates: [better] }));
  assertEquals(res.status, 200);
  const b = await body(res);
  assertEquals(b.subjectScore, 29);
  assertEquals(b.thin, true); // only 1 (< MIN_STRONG 2) but still returned
  const swaps = b.swaps as Record<string, unknown>[];
  assertEquals(swaps.length, 1);
  assertEquals(swaps[0].id, "22222222-2222-2222-2222-222222222222");
  assertEquals(swaps[0].delta, 42); // 71 - 29
  assertEquals(swaps[0].score, 71);
  // additive absence (moderate tier colour) + lower saturated fat, sourced.
  assertEquals(swaps[0].whyBetter, ["No colours E150d", "lower saturated fat"]);
});

// ---------------------------------------------------------------------------
// 3. Allergen filtering
// ---------------------------------------------------------------------------

Deno.test("drops an allergen-conflicting candidate and flags filteredForAllergies", async () => {
  const safe = row({ id: "a", name: "Safe", score: 70, band: "mid", allergensTags: [] });
  const unsafe = row({
    id: "b",
    name: "Has Milk",
    score: 90,
    band: "high",
    allergensTags: ["en:milk"],
  });
  const res = await handleSwaps(
    get(SUBJECT_ID),
    makeDeps({ candidates: [safe, unsafe], allergies: ["milk"] }),
  );
  const b = await body(res);
  assertEquals(b.filteredForAllergies, true);
  const swaps = b.swaps as Record<string, unknown>[];
  assertEquals(swaps.map((s) => s.id), ["a"]); // milk one removed
});

// ---------------------------------------------------------------------------
// 4. Lower/equal/unknown candidates excluded
// ---------------------------------------------------------------------------

Deno.test("excludes lower, equal, and unknown-band candidates", async () => {
  const lower = row({ id: "lo", score: 20, band: "low" });
  const equal = row({ id: "eq", score: 29, band: "low" });
  const unknown = row({ id: "un", score: null, band: "unknown" });
  const higher = row({ id: "hi", score: 55, band: "mid" });
  const res = await handleSwaps(
    get(SUBJECT_ID),
    makeDeps({ candidates: [lower, equal, unknown, higher] }),
  );
  const b = await body(res);
  const swaps = b.swaps as Record<string, unknown>[];
  assertEquals(swaps.map((s) => s.id), ["hi"]);
});

// ---------------------------------------------------------------------------
// 5. Pantry-first ordering beats a larger delta
// ---------------------------------------------------------------------------

Deno.test("pantry candidate sorts above a non-pantry candidate with a larger delta", () => {
  const subject = subjectRow();
  const pantrySmaller = row({ id: "pan", name: "Pantry Pick", score: 50, band: "mid" });
  const biggerDelta = row({ id: "big", name: "Bigger Delta", score: 88, band: "high" });
  const { swaps } = rankSwaps(
    subject,
    [biggerDelta, pantrySmaller],
    new Set(["pan"]),
    [],
  );
  assertEquals(swaps.map((s) => s.id), ["pan", "big"]);
  assertEquals(swaps[0].inPantry, true);
  assertEquals(swaps[1].inPantry, false);
});

// ---------------------------------------------------------------------------
// 6. Subject with no category → honest empty
// ---------------------------------------------------------------------------

Deno.test("subject with empty categories_tags → swaps:[], thin:true, category:null", async () => {
  const subject = subjectRow({ categoriesTags: [] });
  // Even if candidates are supplied, no category = no honest grouping.
  const res = await handleSwaps(
    get(SUBJECT_ID),
    makeDeps({ subject, candidates: [row({ score: 90, band: "high" })] }),
  );
  const b = await body(res);
  assertEquals(b.category, null);
  assertEquals(b.swaps, []);
  assertEquals(b.thin, true);
});

// ---------------------------------------------------------------------------
// 7. No candidate beats the subject → honest empty (200, not error)
// ---------------------------------------------------------------------------

Deno.test("no better candidate → swaps:[], thin:true, still 200", async () => {
  const res = await handleSwaps(
    get(SUBJECT_ID),
    makeDeps({ candidates: [row({ id: "lo", score: 10, band: "low" })] }),
  );
  assertEquals(res.status, 200);
  const b = await body(res);
  assertEquals(b.swaps, []);
  assertEquals(b.thin, true);
});

// ---------------------------------------------------------------------------
// 8. Auth + id validation
// ---------------------------------------------------------------------------

Deno.test("missing Authorization → 401", async () => {
  const res = await handleSwaps(get(SUBJECT_ID, {}), makeDeps({}));
  assertEquals(res.status, 401);
});

Deno.test("bad (non-uuid) id → 400 invalid_id", async () => {
  const res = await handleSwaps(get("not-a-uuid"), makeDeps({}));
  assertEquals(res.status, 400);
  assertEquals((await body(res)).error, "invalid_id");
});

Deno.test("subject not in products → 404 not_found", async () => {
  const res = await handleSwaps(get(SUBJECT_ID), makeDeps({ subject: null }));
  assertEquals(res.status, 404);
  assertEquals((await body(res)).error, "not_found");
});

Deno.test("OPTIONS preflight → 204 with CORS", async () => {
  const req = new Request(`https://x/swaps/product/${SUBJECT_ID}/swaps`, {
    method: "OPTIONS",
  });
  const res = await handleSwaps(req, makeDeps({}));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

// ---------------------------------------------------------------------------
// 9. whyBetter caps at 3 facts; benign-only additive removal → no additive fact
// ---------------------------------------------------------------------------

Deno.test("whyBetter never exceeds 3 facts", () => {
  const subject = subjectRow({
    additivesTags: ["en:e150d", "en:e250", "en:e621"], // 3 moderate/higher
    nutrients: { "saturated-fat_100g": 10, sugars_100g: 50, salt_100g: 1 },
  });
  const candidate = row({
    additivesTags: [], // dropped all three
    nutrients: { "saturated-fat_100g": 1, sugars_100g: 1, salt_100g: 0.01 },
  });
  const facts = whyBetter(subject, candidate);
  assertEquals(facts.length, 3);
});

Deno.test("removing only a benign (low-tier) additive produces no additive fact", () => {
  const subject = subjectRow({
    additivesTags: ["en:e330"], // citric acid, low tier
    nutrients: {},
  });
  const candidate = row({ additivesTags: [], nutrients: {} });
  assertEquals(whyBetter(subject, candidate), []);
});

Deno.test("lower nutrient needs a meaningful (>10%) drop with both values finite", () => {
  const subject = subjectRow({ additivesTags: [], nutrients: { sugars_100g: 10 } });
  // 9.5 is < 10% lower than 10 → not meaningful.
  assertEquals(
    whyBetter(subject, row({ additivesTags: [], nutrients: { sugars_100g: 9.5 } })),
    [],
  );
  // 8 is > 10% lower → emitted.
  assertEquals(
    whyBetter(subject, row({ additivesTags: [], nutrients: { sugars_100g: 8 } })),
    ["lower sugar"],
  );
});

// ---------------------------------------------------------------------------
// 10. Deterministic tie-break by name
// ---------------------------------------------------------------------------

Deno.test("equal (inPantry, delta, score) candidates order by name asc", () => {
  const subject = subjectRow();
  const zebra = row({ id: "z", name: "Zebra", score: 70, band: "mid" });
  const apple = row({ id: "a", name: "Apple", score: 70, band: "mid" });
  const { swaps } = rankSwaps(subject, [zebra, apple], new Set(), []);
  assertEquals(swaps.map((s) => s.name), ["Apple", "Zebra"]);
});

Deno.test("caps results at MAX_SWAPS (5)", () => {
  const subject = subjectRow();
  const many = Array.from(
    { length: 8 },
    (_, i) => row({ id: `c${i}`, name: `C${i}`, score: 50 + i, band: "mid" }),
  );
  const { swaps } = rankSwaps(subject, many, new Set(), []);
  assertEquals(swaps.length, 5);
});
