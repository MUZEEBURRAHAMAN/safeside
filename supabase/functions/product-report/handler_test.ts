/**
 * POST /product-report handler tests — fake deps (no DB, no auth server).
 */

import { assertEquals } from "jsr:@std/assert@1";
import { type Deps, handleReport, type ReportInsert } from "./handler.ts";

const PRODUCT_ID = "22222222-2222-2222-2222-222222222222";
const USER_ID = "33333333-3333-3333-3333-333333333333";

interface FakeState {
  inserts: ReportInsert[];
  userLookups: string[];
}

function makeDeps(opts: {
  userId?: string | null;
  insertError?: Error;
} = {}): { deps: Deps; state: FakeState } {
  const state: FakeState = { inserts: [], userLookups: [] };
  const deps: Deps = {
    getUserId: (token) => {
      state.userLookups.push(token);
      return Promise.resolve("userId" in opts ? opts.userId ?? null : USER_ID);
    },
    insertReport: (row) => {
      if (opts.insertError) return Promise.reject(opts.insertError);
      state.inserts.push(row);
      return Promise.resolve();
    },
  };
  return { deps, state };
}

function request(
  body: unknown,
  init: { method?: string; auth?: boolean } = {},
): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (init.auth !== false) headers["Authorization"] = "Bearer test-jwt";
  return new Request("http://localhost/product-report", {
    method: init.method ?? "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

Deno.test("OPTIONS preflight → 204 with CORS", async () => {
  const { deps } = makeDeps();
  const res = await handleReport(request(undefined, { method: "OPTIONS" }), deps);
  assertEquals(res.status, 204);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("non-POST → 405", async () => {
  const { deps } = makeDeps();
  const res = await handleReport(request(undefined, { method: "GET" }), deps);
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

Deno.test("missing Authorization → 401, no insert", async () => {
  const { deps, state } = makeDeps();
  const res = await handleReport(
    request({ productId: PRODUCT_ID, reason: "other" }, { auth: false }),
    deps,
  );
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
  assertEquals(state.inserts.length, 0);
});

Deno.test("bad UUID → 400", async () => {
  const { deps, state } = makeDeps();
  const res = await handleReport(
    request({ productId: "not-a-uuid", reason: "other" }),
    deps,
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_product_id");
  assertEquals(state.inserts.length, 0);
});

Deno.test("invalid reason → 400", async () => {
  const { deps, state } = makeDeps();
  const res = await handleReport(
    request({ productId: PRODUCT_ID, reason: "made_up" }),
    deps,
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_reason");
  assertEquals(state.inserts.length, 0);
});

Deno.test("valid report → 201 and the row is inserted with a trimmed detail", async () => {
  const { deps, state } = makeDeps();
  const res = await handleReport(
    request({
      productId: PRODUCT_ID,
      reason: "score_off",
      detail: "  the score looks too low  ",
    }),
    deps,
  );
  assertEquals(res.status, 201);
  assertEquals((await res.json()).ok, true);
  assertEquals(state.inserts.length, 1);
  assertEquals(state.inserts[0], {
    productId: PRODUCT_ID,
    reason: "score_off",
    detail: "the score looks too low",
    reporterId: USER_ID,
  });
});

Deno.test("empty / omitted detail is stored as null", async () => {
  const { deps, state } = makeDeps();
  await handleReport(
    request({ productId: PRODUCT_ID, reason: "wrong_info", detail: "   " }),
    deps,
  );
  assertEquals(state.inserts[0].detail, null);

  await handleReport(request({ productId: PRODUCT_ID, reason: "other" }), deps);
  assertEquals(state.inserts[1].detail, null);
});

Deno.test("detail longer than 1000 chars is truncated to 1000", async () => {
  const { deps, state } = makeDeps();
  await handleReport(
    request({ productId: PRODUCT_ID, reason: "other", detail: "x".repeat(1500) }),
    deps,
  );
  assertEquals(state.inserts[0].detail?.length, 1000);
});

Deno.test("reporter_id is null when the JWT cannot be verified (still 201)", async () => {
  const { deps, state } = makeDeps({ userId: null });
  const res = await handleReport(
    request({ productId: PRODUCT_ID, reason: "other" }),
    deps,
  );
  assertEquals(res.status, 201);
  assertEquals(state.inserts[0].reporterId, null);
});

Deno.test("a DB insert error → 500 insert_failed", async () => {
  const { deps } = makeDeps({ insertError: new Error("boom") });
  const res = await handleReport(
    request({ productId: PRODUCT_ID, reason: "other" }),
    deps,
  );
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "insert_failed");
});

Deno.test("malformed JSON body → 400", async () => {
  const { deps } = makeDeps();
  const req = new Request("http://localhost/product-report", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer t" },
    body: "{not json",
  });
  const res = await handleReport(req, deps);
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_body");
});
