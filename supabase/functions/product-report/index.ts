/**
 * Edge Function: POST /product-report (client path POST /functions/v1/product-report)
 *
 * Thin wiring only — validation lives in handler.ts (unit-tested with fake
 * deps). Reports are written with the SERVICE-ROLE key (bypasses RLS); the
 * caller's JWT is verified with a USER-SCOPED client so reporter_id is the
 * authenticated user (null when it can't be verified — the column is nullable).
 *
 * Secrets via env only (platform-injected):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
 */

import { createClient } from "npm:@supabase/supabase-js@2";
import { type Deps, handleReport, type ReportInsert } from "./handler.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const deps: Deps = {
  async getUserId(token: string): Promise<string | null> {
    if (!token || !ANON_KEY) return null;
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });
    const { data, error } = await userClient.auth.getUser(token);
    if (error || !data?.user) return null;
    return data.user.id;
  },

  async insertReport(row: ReportInsert): Promise<void> {
    const { error } = await supabase.from("product_reports").insert({
      product_id: row.productId,
      reason: row.reason,
      detail: row.detail,
      reporter_id: row.reporterId,
    });
    if (error) throw error;
  },
};

Deno.serve((req: Request) => handleReport(req, deps));
