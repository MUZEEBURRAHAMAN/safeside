/**
 * Edge Function: GET swaps/product/:id/swaps
 *
 * Thin wiring only — all ranking + why-better logic lives in handler.ts (pure,
 * unit-tested with fake deps). products / score_results are a GLOBAL cache read
 * with the SERVICE-ROLE key; the caller's own pantry + profile allergies are
 * read with a USER-SCOPED client (their JWT) so RLS keeps them to auth.uid().
 * Any auth problem → empty pantry/allergies (a guest still gets category-ranked
 * swaps, just unfiltered — honest, never crashes).
 *
 * Secrets via env only:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY (platform-injected)
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { SCORE_VERSION } from "../_shared/scoring/engine.ts";
import { type Deps, handleSwaps, type SwapProductRow } from "./handler.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

/** Columns of `products` we need to rank + explain a swap. */
const PRODUCT_COLUMNS =
  "id, barcode, name, brand, images, categories_tags, additives_tags, allergens_tags, nutrients";

interface ProductQueryRow {
  id: string;
  barcode: string | null;
  name: string;
  brand: string | null;
  images: { front?: string | null } | null;
  categories_tags: string[] | null;
  additives_tags: string[] | null;
  allergens_tags: string[] | null;
  nutrients: Record<string, unknown> | null;
}

interface CurrentScore {
  score: number | null;
  band: string;
}

/**
 * Newest score per product_id at the CURRENT score_version only (unknown-band /
 * null scores omitted). Mirrors search/index.ts:getScoresForBarcodes exactly —
 * the transparency rule (never OFF's Nutri-Score; only our current-version
 * band).
 * TODO(chunk-4): read current score from the product_current_scores view
 * instead of reducing latest-by-computed_at in JS.
 */
async function currentScoresFor(
  productIds: string[],
): Promise<Map<string, CurrentScore>> {
  const map = new Map<string, CurrentScore>();
  if (productIds.length === 0) return map;

  const { data, error } = await supabase
    .from("score_results")
    .select("product_id, score, band, score_version, computed_at")
    .in("product_id", productIds)
    .order("computed_at", { ascending: false });
  if (error) throw error;

  for (
    const row of (data ?? []) as {
      product_id: string;
      score: number | null;
      band: string;
      score_version: string;
    }[]
  ) {
    if (map.has(row.product_id)) continue; // keep newest per product
    if (row.score_version !== SCORE_VERSION) continue; // only current version
    if (row.band === "unknown" || row.score === null) continue; // no usable score
    map.set(row.product_id, { score: row.score, band: row.band });
  }
  return map;
}

function toSwapRow(p: ProductQueryRow, score: CurrentScore | undefined): SwapProductRow {
  return {
    id: p.id,
    barcode: p.barcode ?? null,
    name: p.name,
    brand: p.brand ?? null,
    imageURL: p.images?.front ?? null,
    categoriesTags: p.categories_tags ?? [],
    additivesTags: p.additives_tags ?? [],
    allergensTags: p.allergens_tags ?? [],
    nutrients: p.nutrients ?? {},
    score: score?.score ?? null,
    band: score?.band ?? "unknown",
  };
}

function buildDeps(req: Request): Deps {
  const userClient = () => {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !ANON_KEY) return null;
    return createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
  };

  return {
    async getSubject(id: string): Promise<SwapProductRow | null> {
      const { data, error } = await supabase
        .from("products")
        .select(PRODUCT_COLUMNS)
        .eq("id", id)
        .maybeSingle();
      if (error) throw error;
      if (!data) return null;
      const p = data as ProductQueryRow;
      const scores = await currentScoresFor([p.id]);
      return toSwapRow(p, scores.get(p.id));
    },

    async getCandidates(
      categoriesTags: string[],
      excludeId: string,
    ): Promise<SwapProductRow[]> {
      const { data, error } = await supabase
        .from("products")
        .select(PRODUCT_COLUMNS)
        .overlaps("categories_tags", categoriesTags)
        .neq("id", excludeId)
        .limit(40);
      if (error) throw error;
      const rows = (data ?? []) as ProductQueryRow[];
      const scores = await currentScoresFor(rows.map((r) => r.id));
      return rows.map((r) => toSwapRow(r, scores.get(r.id)));
    },

    async getPantryProductIds(): Promise<Set<string>> {
      const client = userClient();
      if (!client) return new Set();
      const { data, error } = await client
        .from("pantry_items")
        .select("product_id");
      if (error || !data) return new Set();
      return new Set((data as { product_id: string }[]).map((r) => r.product_id));
    },

    async getAllergies(): Promise<string[]> {
      const client = userClient();
      if (!client) return [];
      const { data, error } = await client
        .from("profiles")
        .select("allergies")
        .maybeSingle();
      if (error || !data) return [];
      return (data.allergies as string[] | null) ?? [];
    },

    now: () => Date.now(),
  };
}

Deno.serve((req: Request) => handleSwaps(req, buildDeps(req)));
