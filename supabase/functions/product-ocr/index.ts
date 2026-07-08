/**
 * Edge Function: POST /product-ocr  (client path: POST /product/ocr)
 *
 * Thin wiring only — all logic lives in handler.ts (unit-tested with fake
 * deps). Uses the service-role key because products/score_results are
 * writable only by the backend (RLS).
 *
 * No secrets in code: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY come from
 * the environment.
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import type { ScoreOutput } from "../_shared/scoring/engine.ts";
import type { ProductRow } from "../product/handler.ts";
import { type Deps, handleOcr } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

const deps: Deps = {
  async createProduct(row: Omit<ProductRow, "id">) {
    // OCR products have no barcode, so there is nothing to upsert on — each
    // scan creates a fresh provisional row.
    const { data, error } = await supabase
      .from("products")
      .insert(row)
      .select()
      .single();
    if (error) throw error;
    return data as ProductRow;
  },

  async insertScoreResult(productId: string, result: ScoreOutput) {
    const { error } = await supabase.from("score_results").insert({
      product_id: productId,
      score: result.score,
      band: result.band,
      confidence: result.confidence,
      breakdown: { factors: result.factors },
      score_version: result.scoreVersion,
    });
    if (error) throw error;
  },

  now: () => Date.now(),
};

Deno.serve((req: Request) => handleOcr(req, deps));
