/**
 * Edge Function: GET /ingredients/:id  (client path: GET /product/:id/ingredients)
 *
 * Thin wiring only — all logic + guardrails live in handler.ts / _shared/kb.
 * Uses the service-role key: ingredient_kb + ingredient_explanations are a
 * global cache, writable only by the backend (RLS).
 *
 * Secrets via env only:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (platform-injected)
 *   LLM_BASE_URL, LLM_API_KEY, LLM_MODEL     (AI rewrite; absent → raw KB)
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { createLlmClient } from "../_shared/llm.ts";
import type { IngredientOut, KbEntry } from "../_shared/kb/kb.ts";
import { type Deps, handleIngredients, type ProductIngredientsRow } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

const llm = createLlmClient({
  LLM_BASE_URL: Deno.env.get("LLM_BASE_URL"),
  LLM_API_KEY: Deno.env.get("LLM_API_KEY"),
  LLM_MODEL: Deno.env.get("LLM_MODEL"),
});

const deps: Deps = {
  async getProduct(id: string): Promise<ProductIngredientsRow | null> {
    const { data, error } = await supabase
      .from("products")
      .select("additives_tags, ingredients_text")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    if (!data) return null;
    return {
      additivesTags: (data.additives_tags as string[]) ?? [],
      ingredientsText: (data.ingredients_text as string | null) ?? null,
    };
  },

  async getKb(): Promise<KbEntry[]> {
    const { data, error } = await supabase.from("ingredient_kb").select("*");
    if (error) throw error;
    return (data ?? []) as KbEntry[];
  },

  async getCached(ingredientId, kbVersion, locale) {
    const { data, error } = await supabase
      .from("ingredient_explanations")
      .select("explanation")
      .eq("ingredient_id", ingredientId)
      .eq("kb_version", kbVersion)
      .eq("locale", locale)
      .maybeSingle();
    if (error) throw error;
    return (data?.explanation as IngredientOut | undefined) ?? null;
  },

  async saveCached(ingredientId, kbVersion, locale, explanation) {
    const { error } = await supabase
      .from("ingredient_explanations")
      .upsert(
        {
          ingredient_id: ingredientId,
          kb_version: kbVersion,
          locale,
          explanation,
        },
        { onConflict: "ingredient_id,kb_version,locale" },
      );
    if (error) throw error;
  },

  llm,

  now: () => Date.now(),
};

Deno.serve((req: Request) => handleIngredients(req, deps));
