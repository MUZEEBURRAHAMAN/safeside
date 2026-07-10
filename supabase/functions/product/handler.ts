/**
 * GET /product/:barcode — pure handler logic.
 *
 * Kept free of Deno.serve / supabase-js so it is unit-testable with injected
 * dependencies (fetch + db). index.ts wires the real deps.
 *
 * Flow (BACKEND_SPEC §2):
 *   1. Look up products cache by barcode.
 *   2. Fresh hit (fetched_at < 30 days, current score_version) → return cached.
 *   3. Miss/stale → fetch Open Food Facts, map additives to risk tiers,
 *      computeScore, upsert products + score_results, return.
 *   4. Not in OFF → 404 { error: "not_found", needsOcr: true }.
 *
 * The response body decodes into ios/FoodScanner/Models.swift `Product`.
 * When the band is "unknown" the `score` object is OMITTED entirely
 * (Product.score is optional in Swift; ScoreResult.score is not).
 */

import {
  type AdditiveTier,
  computeScore,
  SCORE_VERSION,
  type ScoreFactor,
  type ScoreOutput,
} from "../_shared/scoring/engine.ts";
import additivesRisk from "../_shared/scoring/additives_risk.json" with {
  type: "json",
};
import {
  buildNutrientHighlights,
  type NutrientHighlights,
} from "../_shared/scoring/meters.ts";
import type { OffProduct } from "../_shared/off.ts";
import { isNutrientsThin, mergeNutrients, type UsdaMatch } from "../_shared/usda.ts";

export const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ProductRow {
  id: string;
  barcode: string | null;
  name: string;
  brand: string | null;
  source: string;
  nova_group: number | null;
  nutriscore_grade: string | null;
  nutrients: Record<string, unknown>;
  serving_size: string | null;
  additives_tags: string[];
  allergens_tags: string[];
  categories_tags: string[];
  ingredients_text: string | null;
  images: { front?: string | null } | null;
  data_confidence: "high" | "limited";
  raw_off: unknown;
  fetched_at: string; // ISO timestamp
}

export interface ScoreRow {
  score: number | null;
  band: "high" | "mid" | "low" | "unknown";
  confidence: "high" | "limited";
  breakdown: { factors?: ScoreFactor[] };
  score_version: string;
}

export interface Deps {
  /** products + latest score_results row for a barcode, or null. */
  getProductWithScore(
    barcode: string,
  ): Promise<{ product: ProductRow; score: ScoreRow | null } | null>;
  /** Upsert (on barcode) and return the stored row incl. id. Service role only. */
  upsertProduct(row: Omit<ProductRow, "id">): Promise<ProductRow>;
  /** Insert a score_results row. Service role only. */
  insertScoreResult(
    productId: string,
    result: ScoreOutput,
  ): Promise<void>;
  /** Open Food Facts lookup; null = not found. */
  fetchOff(barcode: string): Promise<OffProduct | null>;
  /**
   * Optional USDA FoodData Central enrichment (fuzzy name/brand match).
   * Absent → no enrichment (OFF-only). Called ONLY on a cache miss/stale
   * re-fetch when OFF nutrients are thin — never on a cache hit. Must resolve
   * to null (not throw) on no-key / no-match / error.
   */
  enrichNutrients?(name: string, brand: string | null): Promise<UsdaMatch | null>;
  /** Clock, injectable for cache-TTL tests. */
  now(): number;
}

// ---------------------------------------------------------------------------
// CORS + JSON helpers
// ---------------------------------------------------------------------------

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Additive tier mapping
// ---------------------------------------------------------------------------

interface RiskEntry {
  tier?: string;
}

const riskTable = additivesRisk as unknown as Record<string, RiskEntry>;

/**
 * Map OFF additives_tags (e.g. "en:e330") to risk tiers via the curated
 * table. Additives we have not reviewed yet are scored as 'low' — absence of
 * review is never treated as evidence of concern — but they are reported back
 * so the detail line can say they are not yet reviewed.
 */
export function mapAdditiveTiers(tags: string[]): {
  tiers: AdditiveTier[];
  unknown: string[];
} {
  const tiers: AdditiveTier[] = [];
  const unknown: string[] = [];
  for (const rawTag of tags) {
    const tag = rawTag.toLowerCase();
    if (tag === "_meta") continue;
    const entry = riskTable[tag];
    const tier = entry?.tier;
    if (tier === "low" || tier === "moderate" || tier === "higher") {
      tiers.push(tier);
    } else {
      tiers.push("low");
      unknown.push(rawTag.replace(/^en:/, "").toUpperCase());
    }
  }
  return { tiers, unknown };
}

/** Neutral note appended to the Additives factor for unreviewed additives. */
function appendUnknownAdditivesNote(
  output: ScoreOutput,
  unknown: string[],
): ScoreOutput {
  if (unknown.length === 0) return output;
  const note = ` ${unknown.length} additive${
    unknown.length > 1 ? "s are" : " is"
  } not yet in our review table (${unknown.join(", ")}) and did not add to the concern count.`;
  return {
    ...output,
    factors: output.factors.map((f) =>
      f.name === "Additives" ? { ...f, detail: f.detail + note } : f
    ),
  };
}

// ---------------------------------------------------------------------------
// Response shaping — must decode into Models.swift `Product`
// ---------------------------------------------------------------------------

interface ScoreBody {
  score: number;
  band: string;
  confidence: string;
  factors: ScoreFactor[];
  scoreVersion: string;
  // Watch-outs / Benefits bar-meters + pre-read counts, computed server-side
  // from product.nutrients (CLAUDE.md #5). Hangs off `score` so an unknown
  // product (no score object) surfaces no meters.
  highlights?: NutrientHighlights;
}

interface ProductBody {
  id: string;
  barcode: string | null;
  name: string;
  brand: string | null;
  imageURL: string | null;
  score?: ScoreBody; // omitted entirely when band is "unknown"
  ingredients: unknown[]; // AI explanations arrive via a later endpoint
  allergens: string[];
  dataConfidence: string;
  fetchedAt: string; // ISO — product.fetched_at, for dated source rows
}

function stripAllergenPrefix(tags: string[]): string[] {
  return tags.map((t) => t.replace(/^[a-z]{2}:/, ""));
}

function buildBody(
  product: ProductRow,
  score: { output: ScoreOutput } | { row: ScoreRow },
): ProductBody {
  const body: ProductBody = {
    id: product.id,
    barcode: product.barcode,
    name: product.name,
    brand: product.brand,
    imageURL: product.images?.front ?? null,
    ingredients: [],
    allergens: stripAllergenPrefix(product.allergens_tags),
    dataConfidence: product.data_confidence,
    fetchedAt: product.fetched_at,
  };

  if ("output" in score) {
    const o = score.output;
    if (o.band !== "unknown" && o.score !== null) {
      body.score = {
        score: o.score,
        band: o.band,
        confidence: o.confidence,
        factors: o.factors,
        scoreVersion: o.scoreVersion,
      };
    }
  } else {
    const r = score.row;
    if (r.band !== "unknown" && r.score !== null) {
      body.score = {
        score: r.score,
        band: r.band,
        confidence: r.confidence,
        factors: r.breakdown.factors ?? [],
        scoreVersion: r.score_version,
      };
    }
  }

  // Meters hang off `score` — never surfaced for an unknown product. Additive
  // tiers are recomputed from the stored tags so the counts are available on
  // BOTH the cache and fresh paths without a re-score.
  if (body.score) {
    const { tiers } = mapAdditiveTiers(product.additives_tags);
    body.score.highlights = buildNutrientHighlights(product.nutrients, tiers);
  }
  return body;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

const BARCODE_RE = /^\d{6,14}$/;

/** Last path segment is the barcode: /product/3017620422003 (works behind
 * the platform prefix /functions/v1/product/... too). */
export function extractBarcode(url: string): string | null {
  const segments = new URL(url).pathname.split("/").filter((s) => s !== "");
  const last = segments[segments.length - 1];
  if (!last || last === "product") return null;
  return last;
}

export async function handleProduct(
  req: Request,
  deps: Deps,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // The platform verifies the JWT (verify_jwt default); we still require the
  // header so unauthenticated local calls fail loudly.
  if (!req.headers.get("Authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  const barcode = extractBarcode(req.url);
  if (!barcode || !BARCODE_RE.test(barcode)) {
    return json(
      { error: "invalid_barcode", detail: "Barcode must be 6-14 digits." },
      400,
    );
  }

  // 1–2. Cache lookup.
  const cached = await deps.getProductWithScore(barcode);
  if (cached) {
    const ageMs = deps.now() - Date.parse(cached.product.fetched_at);
    const fresh = ageMs >= 0 && ageMs < CACHE_TTL_MS;
    const scoreCurrent = cached.score !== null &&
      cached.score.score_version === SCORE_VERSION;
    if (fresh && scoreCurrent) {
      return json(buildBody(cached.product, { row: cached.score! }));
    }
  }

  // 3. Miss / stale → Open Food Facts.
  let off: OffProduct | null;
  try {
    off = await deps.fetchOff(barcode);
  } catch (_err) {
    return json(
      { error: "upstream_error", detail: "Product data source unavailable." },
      502,
    );
  }

  // 4. Not found → client falls back to label OCR.
  if (off === null) {
    return json({ error: "not_found", needsOcr: true }, 404);
  }

  // Enrich thin OFF nutrients from USDA FDC (miss/enrich path only — never on
  // a cache hit). OFF takes precedence; USDA fills gaps. Never breaks the scan.
  let nutriments: Record<string, unknown> = off.nutriments;
  if (deps.enrichNutrients && isNutrientsThin(nutriments)) {
    try {
      const match = await deps.enrichNutrients(off.name, off.brand);
      if (match) {
        const { merged, filled } = mergeNutrients(nutriments, match.nutrients);
        if (filled.length > 0) {
          merged["_enrichment"] = {
            source: "usda",
            fdcId: match.fdcId,
            description: match.description,
            dataType: match.dataType,
            fields: filled,
          };
          nutriments = merged;
        }
      }
    } catch (_err) {
      // USDA is best-effort; fall back to OFF nutrients unchanged.
    }
  }

  // Score it.
  const { tiers, unknown } = mapAdditiveTiers(off.additivesTags);
  const scoreOutput = appendUnknownAdditivesNote(
    computeScore({
      novaGroup: off.novaGroup,
      nutriscoreGrade: off.nutriscoreGrade,
      additiveTiers: tiers,
    }),
    unknown,
  );

  // 5. Upsert cache (service role — clients can never write these tables).
  const nowIso = new Date(deps.now()).toISOString();
  const productRow = await deps.upsertProduct({
    barcode,
    name: off.name,
    brand: off.brand,
    source: "off",
    nova_group: off.novaGroup,
    nutriscore_grade: off.nutriscoreGrade,
    nutrients: nutriments,
    serving_size: off.servingSize,
    additives_tags: off.additivesTags,
    allergens_tags: off.allergensTags,
    categories_tags: off.categoriesTags,
    ingredients_text: off.ingredientsText,
    images: off.imageUrl ? { front: off.imageUrl } : null,
    data_confidence: scoreOutput.confidence,
    raw_off: off.raw,
    fetched_at: nowIso,
  });
  await deps.insertScoreResult(productRow.id, scoreOutput);

  return json(buildBody(productRow, { output: scoreOutput }));
}
