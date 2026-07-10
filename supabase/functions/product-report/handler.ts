/**
 * POST /product-report — file a "Report an issue" submission (Chunk 1).
 *
 * Client path: POST /functions/v1/product-report, body:
 *   { productId: string (uuid), reason: ReportReason, detail?: string }
 *
 * Retrieval/validation only — no LLM, no product lookup. Rows are written with
 * the service-role key (index.ts); the caller's JWT is verified to derive a
 * reporter_id (null on failure is acceptable — the column is nullable). Pure
 * and I/O-free except through injected `Deps`, so it runs offline in tests.
 */

// ---------------------------------------------------------------------------
// CORS + JSON helpers
// ---------------------------------------------------------------------------

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------------------
// Contract
// ---------------------------------------------------------------------------

/** Accepted reasons — must match the report_reason_type enum + iOS ReportReason. */
export const REPORT_REASONS = [
  "score_off",
  "wrong_info",
  "missing_ingredient",
  "other",
] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

export const MAX_DETAIL_CHARS = 1000;

export interface ReportInsert {
  productId: string;
  reason: string;
  detail: string | null;
  reporterId: string | null;
}

export interface Deps {
  /** Verify the bearer token → the caller's user id, or null on failure. */
  getUserId(token: string): Promise<string | null>;
  /** Insert one report (service role). Throws on a DB error. */
  insertReport(row: ReportInsert): Promise<void>;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function bearerToken(header: string): string {
  return header.replace(/^Bearer\s+/i, "").trim();
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleReport(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: { productId?: unknown; reason?: unknown; detail?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const productId = typeof body.productId === "string" ? body.productId : "";
  if (!UUID_RE.test(productId)) {
    return json({ error: "invalid_product_id" }, 400);
  }

  const reason = body.reason;
  if (typeof reason !== "string" || !REPORT_REASONS.includes(reason as ReportReason)) {
    return json({ error: "invalid_reason" }, 400);
  }

  // Optional free text: trim, drop when empty, truncate to the column cap.
  let detail: string | null = null;
  if (typeof body.detail === "string") {
    const trimmed = body.detail.trim();
    if (trimmed !== "") detail = trimmed.slice(0, MAX_DETAIL_CHARS);
  }

  // Best-effort reporter identity; null is acceptable (nullable column).
  const reporterId = await deps.getUserId(bearerToken(auth));

  try {
    await deps.insertReport({ productId, reason, detail, reporterId });
  } catch {
    return json({ error: "insert_failed" }, 500);
  }

  return json({ ok: true }, 201);
}
