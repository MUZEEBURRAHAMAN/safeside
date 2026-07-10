/**
 * Edge Function: POST /rescore  (client path: POST /functions/v1/rescore)
 *
 * Thin wiring only — all re-score logic lives in handler.ts (pure, unit-tested
 * with fake deps). products / score_results / product_current_scores are read
 * and written with the SERVICE-ROLE key; clients can never write score_results.
 *
 * NOT publicly triggerable: every call must carry the shared secret header
 * `X-Rescore-Secret` matching `RESCORE_SECRET` (a deploy-gate env var kept out
 * of the repo). An anon JWT alone is NOT enough — the pg_cron job passes the
 * secret. Missing/wrong secret → 401.
 *
 * Secrets via env only:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (platform-injected)
 *   RESCORE_SECRET (function secret; set via `supabase secrets set`)
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { SCORE_VERSION } from "../_shared/scoring/engine.ts";
import { type Deps, handleRescore, type StaleProduct } from "./handler.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESCORE_SECRET = Deno.env.get("RESCORE_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-rescore-secret",
};

interface ProductRow {
  id: string;
  source: string;
  raw_off: unknown;
}

interface CurrentScoreRow {
  product_id: string;
  score_version: string;
}

function buildDeps(): Deps {
  return {
    async findStaleProducts(
      currentVersion: string,
      limit: number,
    ): Promise<StaleProduct[]> {
      // Current score_version per product (one row each via the view).
      const { data: scoreRows, error: sErr } = await supabase
        .from("product_current_scores")
        .select("product_id, score_version");
      if (sErr) throw sErr;
      const versionByProduct = new Map<string, string>();
      for (const r of (scoreRows ?? []) as CurrentScoreRow[]) {
        versionByProduct.set(r.product_id, r.score_version);
      }

      // Products whose current version differs (or that have no score at all).
      const { data: products, error: pErr } = await supabase
        .from("products")
        .select("id, source, raw_off")
        .order("fetched_at", { ascending: true });
      if (pErr) throw pErr;

      const stale: StaleProduct[] = [];
      for (const p of (products ?? []) as ProductRow[]) {
        const version = versionByProduct.get(p.id) ?? null;
        if (version === currentVersion) continue; // up to date
        stale.push({
          id: p.id,
          source: p.source,
          currentVersion: version,
          raw_off: p.raw_off,
        });
        if (stale.length >= limit) break;
      }
      return stale;
    },

    async insertScoreResult(productId, result): Promise<void> {
      const { error } = await supabase.from("score_results").insert({
        product_id: productId,
        score: result.score,
        band: result.band,
        breakdown: { factors: result.factors },
        confidence: result.confidence,
        score_version: result.scoreVersion,
      });
      if (error) throw error;
    },

    now: () => Date.now(),
  };
}

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  // Secret gate — reject anything that doesn't carry the shared secret. Never
  // reveal whether the secret is configured; a constant-time-ish equality is
  // sufficient here (short, fixed-length secret over TLS).
  const provided = req.headers.get("x-rescore-secret") ?? "";
  if (!RESCORE_SECRET || provided !== RESCORE_SECRET) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
  // Touch SCORE_VERSION import so the wiring is self-documenting (handler uses it).
  void SCORE_VERSION;
  return handleRescore(req, buildDeps());
});
