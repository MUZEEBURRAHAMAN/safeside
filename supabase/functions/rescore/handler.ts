/**
 * POST /rescore — re-score cached products after a SCORE_VERSION bump.
 * Chunk 4, Task 5.
 *
 * When the scoring engine's version changes (a weight/additive-tier change the
 * dietitian signs off), every cached product's CURRENT score becomes stale.
 * This endpoint reconstructs each stale product's score INPUTS from what we
 * already stored (`raw_off`) and re-runs the SAME deterministic engine
 * (`computeScore`) — the LLM is never involved (CLAUDE.md #5). A fresh
 * `score_results` row is inserted (history preserved), so `product_current_scores`
 * immediately returns the new score.
 *
 * Not publicly triggerable: `index.ts` gates every call behind an
 * `X-Rescore-Secret` header (== `RESCORE_SECRET`); the pg_cron job passes it.
 * This pure handler stays secret-free so it is fully unit-testable offline.
 *
 * Input reconstruction:
 *   - source "off": mapOffPayload(raw_off) → { novaGroup, nutriscoreGrade,
 *     additivesTags } → mapAdditiveTiers → computeScore (+ unreviewed-additive
 *     note). Unmappable payloads are skipped (log-and-continue), never aborting
 *     the batch.
 *   - source "ocr": raw_off.parsed.additivesTags → tiers → computeScore with
 *     no NOVA / Nutri-Score → band "unknown" (the honest OCR result).
 */

import {
  computeScore,
  SCORE_VERSION,
  type ScoreOutput,
} from "../_shared/scoring/engine.ts";
import { mapAdditiveTiers } from "../product/handler.ts";
import { mapOffPayload } from "../_shared/off.ts";

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-rescore-secret",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A cached product whose CURRENT score is at a stale score_version (or which
 * has no score row at all → currentVersion null). */
export interface StaleProduct {
  id: string;
  source: string; // "off" | "ocr" | ...
  currentVersion: string | null;
  raw_off: unknown;
}

export interface Deps {
  /** Products whose current score_version != `currentVersion` (or unscored),
   * capped at `limit`. Service role. */
  findStaleProducts(currentVersion: string, limit: number): Promise<StaleProduct[]>;
  /** Insert a fresh score_results row (history preserved). Service role. */
  insertScoreResult(productId: string, result: ScoreOutput): Promise<void>;
  now(): number;
}

interface RescoreReport {
  id: string;
  from: string | null;
  to: string;
}

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 1000;

// ---------------------------------------------------------------------------
// Additive-note helper (mirrors product/handler's unreviewed-additive note so
// re-scored OFF products carry the same neutral detail line).
// ---------------------------------------------------------------------------

function appendUnknownAdditivesNote(
  output: ScoreOutput,
  unknown: string[],
): ScoreOutput {
  if (unknown.length === 0) return output;
  const note = ` ${unknown.length} additive${
    unknown.length > 1 ? "s are" : " is"
  } not yet in our review table (${
    unknown.join(", ")
  }) and did not add to the concern count.`;
  return {
    ...output,
    factors: output.factors.map((f) =>
      f.name === "Additives" ? { ...f, detail: f.detail + note } : f
    ),
  };
}

// ---------------------------------------------------------------------------
// Score reconstruction (pure)
// ---------------------------------------------------------------------------

interface OcrRawOff {
  parsed?: { additivesTags?: unknown };
}

/** Recompute a product's ScoreOutput from its stored raw_off, or null when the
 * inputs can't be reconstructed (bad OFF payload) → the batch skips it. */
export function rescoreProduct(product: StaleProduct): ScoreOutput | null {
  if (product.source === "ocr") {
    const raw = product.raw_off as OcrRawOff | null;
    const tagsRaw = raw?.parsed?.additivesTags;
    const additivesTags = Array.isArray(tagsRaw)
      ? tagsRaw.filter((t): t is string => typeof t === "string")
      : [];
    const { tiers, unknown } = mapAdditiveTiers(additivesTags);
    return appendUnknownAdditivesNote(
      computeScore({ novaGroup: null, nutriscoreGrade: null, additiveTiers: tiers }),
      unknown,
    );
  }

  // Default: OFF-style payload.
  const off = mapOffPayload(product.raw_off);
  if (off === null) return null; // unmappable → skip, never abort the batch
  const { tiers, unknown } = mapAdditiveTiers(off.additivesTags);
  return appendUnknownAdditivesNote(
    computeScore({
      novaGroup: off.novaGroup,
      nutriscoreGrade: off.nutriscoreGrade,
      additiveTiers: tiers,
    }),
    unknown,
  );
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleRescore(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const dryRun = new URL(req.url).searchParams.get("dryRun") === "1";

  let limit = DEFAULT_LIMIT;
  try {
    const body = await req.json();
    if (body && typeof body === "object") {
      const raw = (body as { limit?: unknown }).limit;
      if (typeof raw === "number" && Number.isFinite(raw)) {
        limit = Math.min(MAX_LIMIT, Math.max(1, Math.floor(raw)));
      }
    }
  } catch {
    // No/invalid body → default limit.
  }

  const stale = await deps.findStaleProducts(SCORE_VERSION, limit);

  const products: RescoreReport[] = [];
  let rescored = 0;
  let skipped = 0;

  for (const p of stale) {
    const output = rescoreProduct(p);
    if (output === null) {
      skipped += 1;
      continue;
    }
    if (!dryRun) {
      await deps.insertScoreResult(p.id, output);
    }
    rescored += 1;
    products.push({ id: p.id, from: p.currentVersion, to: output.scoreVersion });
  }

  return json({
    scanned: stale.length,
    rescored,
    skipped,
    dryRun,
    products,
  });
}
