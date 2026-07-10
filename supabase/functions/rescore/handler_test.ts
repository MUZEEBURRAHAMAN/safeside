/**
 * POST /rescore handler tests — fake deps (no DB, no network).
 *
 * Re-scoring re-runs the SAME deterministic engine over a cached product's
 * stored inputs and inserts a fresh score_results row at the current
 * SCORE_VERSION. These tests pin: only stale products are touched, dryRun
 * inserts nothing, OFF products recompute to a real number, OCR products stay
 * band "unknown", and an all-current cache is a no-op.
 */

import { assertEquals } from "jsr:@std/assert@1";
import { SCORE_VERSION } from "../_shared/scoring/engine.ts";
import { type Deps, handleRescore, type StaleProduct } from "./handler.ts";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

let idSeq = 0;
function nextId(): string {
  idSeq += 1;
  return `00000000-0000-0000-0000-${String(idSeq).padStart(12, "0")}`;
}

/** A cached OFF product carrying the full OFF envelope as raw_off. */
function offProductAtVersion(version: string): StaleProduct {
  return {
    id: nextId(),
    source: "off",
    currentVersion: version,
    raw_off: {
      status: 1,
      code: "123",
      product: {
        product_name: "Test OFF product",
        nova_group: 4,
        nutriscore_grade: "d",
        additives_tags: ["en:e330"],
      },
    },
  };
}

/** A cached OCR product: no NOVA / Nutri-Score, only parsed additive tags. */
function ocrProductAtVersion(version: string): StaleProduct {
  return {
    id: nextId(),
    source: "ocr",
    currentVersion: version,
    raw_off: { source: "ocr", parsed: { additivesTags: ["en:e330"] } },
  };
}

interface InsertedRow {
  productId: string;
  score: number | null;
  band: string;
  score_version: string;
}

function makeDeps(
  opts: { stale?: StaleProduct[]; current?: StaleProduct[] },
): { deps: Deps; state: { inserted: InsertedRow[] } } {
  const all = [...(opts.stale ?? []), ...(opts.current ?? [])];
  const state = { inserted: [] as InsertedRow[] };
  const deps: Deps = {
    // Emulates the real query: only products whose CURRENT score_version differs
    // from the engine's current version (or that have no score) are returned.
    findStaleProducts(currentVersion: string, limit: number) {
      const stale = all
        .filter((p) => p.currentVersion !== currentVersion)
        .slice(0, limit);
      return Promise.resolve(stale);
    },
    insertScoreResult(productId, output) {
      state.inserted.push({
        productId,
        score: output.score,
        band: output.band,
        score_version: output.scoreVersion,
      });
      return Promise.resolve();
    },
    now: () => Date.parse("2026-07-10T00:00:00Z"),
  };
  return { deps, state };
}

function request(body: unknown, init: { query?: string } = {}): Request {
  return new Request(`http://localhost/rescore${init.query ?? ""}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("rescore selects only products whose current score_version is stale", async () => {
  const { deps, state } = makeDeps({
    stale: [offProductAtVersion("1.0.0")],
    current: [offProductAtVersion(SCORE_VERSION)],
  });
  const res = await handleRescore(request({}), deps);
  assertEquals(res.status, 200);
  assertEquals(state.inserted.length, 1); // only the stale one re-scored
});

Deno.test("rescore dryRun inserts nothing but reports the stale product", async () => {
  const { deps, state } = makeDeps({ stale: [offProductAtVersion("1.0.0")] });
  const res = await handleRescore(request({}, { query: "?dryRun=1" }), deps);
  const body = await res.json();
  assertEquals(body.dryRun, true);
  assertEquals(body.products.length, 1);
  assertEquals(state.inserted.length, 0);
});

Deno.test("rescore recomputes an OFF product deterministically from raw_off", async () => {
  const { deps, state } = makeDeps({ stale: [offProductAtVersion("1.0.0")] });
  await handleRescore(request({}), deps);
  assertEquals(state.inserted[0].score_version, SCORE_VERSION);
  assertEquals(typeof state.inserted[0].score, "number"); // real number for OFF
});

Deno.test("rescore keeps an OCR product at band unknown (no NOVA/Nutri-Score)", async () => {
  const { deps, state } = makeDeps({ stale: [ocrProductAtVersion("1.0.0")] });
  await handleRescore(request({}), deps);
  assertEquals(state.inserted[0].band, "unknown");
  assertEquals(state.inserted[0].score, null);
});

Deno.test("rescore is a no-op when everything is current", async () => {
  const { deps, state } = makeDeps({ current: [offProductAtVersion(SCORE_VERSION)] });
  const res = await handleRescore(request({}), deps);
  const body = await res.json();
  assertEquals(state.inserted.length, 0);
  assertEquals(body.rescored, 0);
  assertEquals(body.scanned, 0);
});

Deno.test("rescore reports from/to versions per product", async () => {
  const { deps } = makeDeps({ stale: [offProductAtVersion("1.0.0")] });
  const res = await handleRescore(request({}), deps);
  const body = await res.json();
  assertEquals(body.products[0].from, "1.0.0");
  assertEquals(body.products[0].to, SCORE_VERSION);
});

Deno.test("rescore skips (does not abort on) a product with unmappable raw_off", async () => {
  const bad: StaleProduct = {
    id: nextId(),
    source: "off",
    currentVersion: "1.0.0",
    raw_off: { status: 0 }, // OFF "not found" envelope → mapOffPayload returns null
  };
  const { deps, state } = makeDeps({ stale: [bad, offProductAtVersion("1.0.0")] });
  const res = await handleRescore(request({}), deps);
  const body = await res.json();
  assertEquals(res.status, 200);
  assertEquals(state.inserted.length, 1); // the good one still re-scored
  assertEquals(body.scanned, 2);
  assertEquals(body.rescored, 1);
});
