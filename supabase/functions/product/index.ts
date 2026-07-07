/**
 * Edge Function: GET /product/:barcode
 *
 * Thin wiring only — all logic lives in handler.ts (unit-tested with fake
 * deps). Uses the service-role key (injected by the platform) because
 * products/score_results are writable only by the backend (RLS).
 *
 * No secrets in code: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY come from
 * the environment.
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { fetchProduct } from "../_shared/off.ts";
import type { ScoreOutput } from "../_shared/scoring/engine.ts";
import {
  type Deps,
  handleProduct,
  type ProductRow,
  type ScoreRow,
} from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

const deps: Deps = {
  async getProductWithScore(barcode: string) {
    const { data: product, error } = await supabase
      .from("products")
      .select("*")
      .eq("barcode", barcode)
      .maybeSingle();
    if (error) throw error;
    if (!product) return null;

    const { data: scores, error: scoreError } = await supabase
      .from("score_results")
      .select("*")
      .eq("product_id", product.id)
      .order("computed_at", { ascending: false })
      .limit(1);
    if (scoreError) throw scoreError;

    return {
      product: product as ProductRow,
      score: (scores?.[0] as ScoreRow | undefined) ?? null,
    };
  },

  async upsertProduct(row: Omit<ProductRow, "id">) {
    const { data, error } = await supabase
      .from("products")
      .upsert(row, { onConflict: "barcode" })
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

  fetchOff: (barcode: string) => fetchProduct(barcode),

  now: () => Date.now(),
};

Deno.serve((req: Request) => handleProduct(req, deps));
