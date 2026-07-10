/**
 * GET /search?q=<term> — pure handler logic.
 *
 * Name-search over Open Food Facts, mapped to our normalized SearchResult
 * shape. Kept free of Deno.serve / supabase-js so it is unit-testable with
 * injected dependencies (OFF search + our cached scores). index.ts wires the
 * real deps.
 *
 * Transparency (CLAUDE.md #1 + teardown AVOID #5): a row carries a `score`
 * object ONLY when WE have a cached score for that barcode at the CURRENT
 * SCORE_VERSION and it isn't the "unknown" band. We never surface OFF's own
 * Nutri-Score as if it were ours. Unscored rows omit `score` → the client
 * shows a neutral "Not scored yet" affordance, never a false-reassurance color.
 *
 * The response body decodes into ios/FoodScanner/Models.swift `SearchResult`.
 * A typed barcode never reaches here — the client routes barcodes straight to
 * the existing scored `/product/:barcode` path (identical to a live scan).
 */

import { SCORE_VERSION } from "../_shared/scoring/engine.ts";
import type { OffProduct } from "../_shared/off.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A cached score for one barcode, as returned by the DB lookup. */
export interface ScoreEntry {
  score: number;
  band: string;
  score_version: string;
}

export interface Deps {
  /** OFF name search → mapped products (no scores attached). Throws → 502. */
  searchOff(query: string): Promise<OffProduct[]>;
  /** Our latest cached score per barcode (service role). Absent barcodes omitted. */
  getScoresForBarcodes(barcodes: string[]): Promise<Map<string, ScoreEntry>>;
}

/** One search row — decodes into Swift `SearchResult`. */
interface SearchResult {
  barcode: string;
  name: string;
  brand: string | null;
  imageURL: string | null;
  /** Present ONLY for barcodes we've scored at the current version. */
  score?: { score: number; band: string };
}

const MAX_QUERY_LEN = 100;

// ---------------------------------------------------------------------------
// CORS + JSON helpers (copied locally — handlers stay decoupled, as today)
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
// Query extraction
// ---------------------------------------------------------------------------

export function extractQuery(url: string): string {
  return new URL(url).searchParams.get("q")?.trim() ?? "";
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleSearch(
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

  const rawQuery = extractQuery(req.url);
  if (rawQuery === "") {
    return json({ error: "empty_query" }, 400);
  }
  const query = rawQuery.slice(0, MAX_QUERY_LEN);

  // OFF name search (never on the barcode path — that's client-routed).
  let offs: OffProduct[];
  try {
    offs = await deps.searchOff(query);
  } catch (_err) {
    return json({ error: "upstream_error" }, 502);
  }

  // Drop rows with no barcode or the "Unknown product" name fallback (a
  // nameless row is useless), then join OUR cached scores.
  const usable = offs.filter(
    (p) => p.barcode !== "" && p.name !== "" && p.name !== "Unknown product",
  );

  const scores = usable.length === 0
    ? new Map<string, ScoreEntry>()
    : await deps.getScoresForBarcodes(usable.map((p) => p.barcode));

  const results: SearchResult[] = usable.map((p) => {
    const row: SearchResult = {
      barcode: p.barcode,
      name: p.name,
      brand: p.brand,
      imageURL: p.imageUrl,
    };
    // Attach a score ONLY when it's ours, current, and a real band.
    const cached = scores.get(p.barcode);
    if (
      cached &&
      cached.score_version === SCORE_VERSION &&
      cached.band !== "unknown"
    ) {
      row.score = { score: cached.score, band: cached.band };
    }
    return row;
  });

  return json({ results });
}
