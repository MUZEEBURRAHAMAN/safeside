/**
 * Edge Function: POST /chat  (client path: POST /functions/v1/chat)
 *
 * Thin wiring only — all grounding + guardrails live in handler.ts (unit-tested
 * with fake deps). products / score_results / ingredient_kb are a global cache
 * read with the SERVICE-ROLE key; the caller's own profile is read with a
 * USER-SCOPED client (their JWT) so RLS keeps it to auth.uid().
 *
 * Secrets via env only:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY (platform-injected)
 *   LLM_BASE_URL, LLM_API_KEY, LLM_MODEL   (AI reply; absent → canned reply)
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { createLlmClient } from "../_shared/llm.ts";
import type { KbEntry } from "../_shared/kb/kb.ts";
import type { ScoreFactor } from "../_shared/scoring/engine.ts";
import {
  type ChatProductRow,
  type ChatProfile,
  type ChatScoreRow,
  type Deps,
  handleChat,
} from "./handler.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const llm = createLlmClient({
  LLM_BASE_URL: Deno.env.get("LLM_BASE_URL"),
  LLM_API_KEY: Deno.env.get("LLM_API_KEY"),
  LLM_MODEL: Deno.env.get("LLM_MODEL"),
});

/** Decode the JWT `sub` (the user id; anon sessions carry one too) without
 * verifying — the platform already verified the token before this function
 * runs; we only need the id to key the rate-limit ledger. */
function jwtSub(req: Request): string | null {
  const auth = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!auth) return null;
  try {
    const payload = JSON.parse(atob(auth.split(".")[1] ?? ""));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

function buildDeps(req: Request): Deps {
  return {
    async getProduct(id: string): Promise<ChatProductRow | null> {
      const { data, error } = await supabase
        .from("products")
        .select(
          "name, brand, nova_group, nutriscore_grade, serving_size, nutrients, additives_tags, allergens_tags, ingredients_text",
        )
        .eq("id", id)
        .maybeSingle();
      if (error) throw error;
      if (!data) return null;
      return {
        name: data.name as string,
        brand: (data.brand as string | null) ?? null,
        novaGroup: (data.nova_group as number | null) ?? null,
        nutriscoreGrade: (data.nutriscore_grade as string | null) ?? null,
        servingSize: (data.serving_size as string | null) ?? null,
        nutrients: (data.nutrients as Record<string, unknown>) ?? {},
        additivesTags: (data.additives_tags as string[]) ?? [],
        allergensTags: (data.allergens_tags as string[]) ?? [],
        ingredientsText: (data.ingredients_text as string | null) ?? null,
      };
    },

    async getScore(productId: string): Promise<ChatScoreRow | null> {
      const { data, error } = await supabase
        .from("score_results")
        .select("score, band, confidence, breakdown")
        .eq("product_id", productId)
        .order("computed_at", { ascending: false })
        .limit(1);
      if (error) throw error;
      const row = data?.[0];
      if (!row) return null;
      const breakdown = row.breakdown as { factors?: ScoreFactor[] } | null;
      return {
        score: (row.score as number | null) ?? null,
        band: row.band as string,
        confidence: row.confidence as string,
        factors: breakdown?.factors ?? [],
      };
    },

    async getKb(): Promise<KbEntry[]> {
      const { data, error } = await supabase.from("ingredient_kb").select("*");
      if (error) throw error;
      return (data ?? []) as KbEntry[];
    },

    // Best-effort personalization: read the caller's own profile under RLS via
    // a user-scoped client. Any problem (anon user, no row, no key) → null.
    async getProfile(): Promise<ChatProfile | null> {
      const authHeader = req.headers.get("Authorization");
      if (!authHeader || !ANON_KEY) return null;
      const userClient = createClient(SUPABASE_URL, ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false },
      });
      const { data, error } = await userClient
        .from("profiles")
        .select("allergies, health_flags, diet_pattern")
        .maybeSingle();
      if (error || !data) return null;
      return {
        allergies: (data.allergies as string[]) ?? [],
        healthFlags: (data.health_flags as string[]) ?? [],
        dietPattern: (data.diet_pattern as string | null) ?? null,
      };
    },

    llm,

    now: () => Date.now(),

    // --- Rate-limit ledger (service role; clients can neither read nor write
    // chat_rate_events). Keyed by the JWT sub so anon sessions are limited too.
    userId: () => jwtSub(req),

    async recentChatRequests(userId: string): Promise<number[]> {
      const since = new Date(Date.now() - 60_000).toISOString();
      const { data } = await supabase
        .from("chat_rate_events")
        .select("created_at")
        .eq("user_id", userId)
        .gte("created_at", since);
      return (data ?? []).map((r) => Date.parse(r.created_at as string));
    },

    async recordChatRequest(userId: string): Promise<void> {
      await supabase.from("chat_rate_events").insert({ user_id: userId });
    },
  };
}

Deno.serve((req: Request) => handleChat(req, buildDeps(req)));
