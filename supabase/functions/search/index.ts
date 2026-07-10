/**
 * Edge Function: GET /search?q=<term>
 *
 * Thin wiring only — all logic lives in handler.ts (unit-tested with fake
 * deps). Uses the service-role key (injected by the platform) because
 * products/score_results are readable only by the backend (RLS); clients can
 * never read those tables directly.
 *
 * No secrets in code: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY come from
 * the environment.
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { fetchOffSearch } from "../_shared/off.ts";
import { type Deps, handleSearch, type ScoreEntry } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

const deps: Deps = {
  searchOff: (q: string) => fetchOffSearch(q),

  async getScoresForBarcodes(barcodes: string[]) {
    const map = new Map<string, ScoreEntry>();
    if (barcodes.length === 0) return map;

    // products: barcode ↔ id, for the barcodes OFF returned.
    const { data: products, error: pErr } = await supabase
      .from("products")
      .select("id,barcode")
      .in("barcode", barcodes);
    if (pErr) throw pErr;
    if (!products || products.length === 0) return map;

    const idToBarcode = new Map<string, string>();
    for (const p of products as { id: string; barcode: string | null }[]) {
      if (p.barcode) idToBarcode.set(p.id, p.barcode);
    }

    // Latest score_results per product_id. Ordered newest-first; we keep the
    // first (newest) row seen per product.
    // TODO(chunk-4): read the product_current_scores view once it lands.
    const { data: scores, error: sErr } = await supabase
      .from("score_results")
      .select("product_id,score,band,score_version,computed_at")
      .in("product_id", [...idToBarcode.keys()])
      .order("computed_at", { ascending: false });
    if (sErr) throw sErr;

    for (
      const row of (scores ?? []) as {
        product_id: string;
        score: number | null;
        band: string;
        score_version: string;
      }[]
    ) {
      const barcode = idToBarcode.get(row.product_id);
      if (!barcode || map.has(barcode)) continue; // keep newest per product
      if (row.score === null) continue; // unknown band has a null score
      map.set(barcode, {
        score: row.score,
        band: row.band,
        score_version: row.score_version,
      });
    }
    return map;
  },
};

Deno.serve((req: Request) => handleSearch(req, deps));
