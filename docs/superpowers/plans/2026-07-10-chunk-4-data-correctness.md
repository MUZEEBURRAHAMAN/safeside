# Chunk 4 — Data & Correctness Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax `- [ ]`. Backend-heavy chunk: TDD every pure function (Deno tests BEFORE implementation); the iOS edits are a thin swap to a new DB view.

**Goal:** Close the five data-correctness gaps from MASTER_PLAN §Chunk 4 so trending/swaps/search read the *current* score (not highest-ever), OCR stops emitting redundant additive-class orphans, `/chat` is rate-limited before it ships publicly, cached products auto-re-score on a `score_version` bump, and the dietitian gets an exportable weights sheet.

**Architecture:** Mostly backend. **New files:** one SQL migration (`product_current_scores` view + `chat_rate_events` table + `pg_cron`/`pg_net` re-score schedule), one new edge function `rescore/` (`index.ts` + `handler.ts` + `handler_test.ts`), and one dietitian review doc. **Edits:** `supabase/functions/chat/handler.ts` + `chat/index.ts` (sliding-window rate limit), `supabase/functions/product-ocr/handler.ts` (parenthetical-orphan drop), and iOS `PantryService.swift` (read the new view for trending + recent). **Schema/RLS:** the view is `security_invoker = true` so it inherits `score_results`' existing global-read RLS (no new grant of write); `chat_rate_events` is RLS-enabled with **no** client policies (service-role writes only, exactly like `products`). No client-facing table is exposed for writes.

**Tech Stack:** Supabase Postgres 15 (SQL views, `pg_cron`, `pg_net`), Deno + `@std/assert@1` edge functions, the existing pure scoring engine (`_shared/scoring/engine.ts`, `SCORE_VERSION = "1.1.0"`), `_shared/off.ts` `mapOffPayload`, SwiftUI + `supabase-swift` client (`@Observable` `PantryService`).

---

## Dependencies & sequencing note

Per MASTER_PLAN §Sequencing (`0 → 1 → 2 → 3 → 4 → …`):

- **Chunk 3 (Swaps) should land first.** Chunk 3's plan is told to compute "current score" **inline** if it runs before Chunk 4, then *switch to the `product_current_scores` view once this chunk lands*. **Task 1 of this chunk creates that view; if Chunk 3 already shipped, Task 1 also includes migrating the swaps ranking query from its inline computation to the view** (grep `product_current_scores` after Task 1 to confirm swaps reads it). If Chunk 3 has **not** shipped yet, build the view anyway — trending (already live) needs it — and leave a note in the swaps plan to read it.
- **Chunk 2 (Search) is upstream of the view read for search results**, but search normalization is independent; if Search isn't built yet, this chunk still ships the view and only wires *trending + recent*. Add search wiring when Chunk 2 lands (one-line note in that plan).
- **Chunk 0 is DONE** (`PantryService.remove`, honest copy, tokens) — this chunk edits the same file; rebase on current `main`.
- The **rate-limit** and **re-score cron** are self-contained backend work with no chunk dependency — they can execute in any order relative to 1/2/3.
- ⚠️ **Column-name reality check:** MASTER_PLAN says "top-1 per product by `scored_at`". The real column in `score_results` is **`computed_at`** (migration `20260707000000_initial_schema.sql:84`). Use `computed_at`. There is no `scored_at` column.

---

## Global Constraints

- **LLM never does math** (CLAUDE.md #5): re-score reuses the deterministic `computeScore`; the view is pure SQL. No model involvement anywhere in this chunk.
- **Transparent + honest states:** trending must show the score a user would see today; the "highest-ever" surfacing is a correctness bug, not a nicety.
- **Copy** from `docs/COPY_DECK.md` only — the 429 body uses the existing §"Offline & limits" string verbatim; never invent inline copy.
- **Deno:** `cd supabase/functions && deno task test` must stay green (**121 tests today** — never regress); new tests add to that count. Format to `lineWidth: 90` (`deno fmt`), lint clean (`deno lint`).
- **iOS:** `cd ios && xcodegen generate && xcodebuild … build` before every screenshot (project file is generated — STATE.md gotcha). `deno task test` + iOS build both green before device install.
- **RLS discipline:** clients never gain write access to `score_results`, the new view, or `chat_rate_events`. All writes are service-role from edge functions / cron.

---

### Task 1: `product_current_scores` DB view (fixes the highest-ever bug)

**New file:** `supabase/migrations/20260710000000_current_scores_view.sql`
**Reads target the view from:** `ios/FoodScanner/PantryService.swift` `loadTrending` (135–190) and `loadRecent` (~83–89).

The bug (self-documented in `PantryService.swift:123-133`): `loadTrending` fetches `score_results` ordered by `score` desc across **all history**, then keeps the first row per product — so a product scored high once and later downgraded can still surface, and it surfaces its *highest-ever* score, not its current one.

- [ ] **Write the migration.** One row per product = its most-recently-computed score:
```sql
-- product_current_scores: exactly one row per product — its latest score_results
-- row by computed_at. Feeds trending, swaps, and search so they never show a
-- stale highest-ever score. security_invoker=true → inherits score_results'
-- global-read RLS (no new write surface).
create view product_current_scores
  with (security_invoker = true)
as
  select distinct on (product_id)
    id, product_id, score, band, confidence, breakdown, score_version, computed_at
  from score_results
  order by product_id, computed_at desc;

grant select on product_current_scores to authenticated, anon;
```
- [ ] Confirm the view's columns are a superset of the Swift `ScoreResultRow` decode set (`id, product_id, score, band, confidence, score_version, computed_at` — `PantryModels.swift:252-267`) so the client decodes it unchanged.
- [ ] **Deploy + verify (SQL):** apply via `supabase db push` (or the Management API SQL endpoint per STATE.md:62). Verify against real history:
```sql
-- Must equal: newest score_results row per product.
select v.product_id, v.score, v.computed_at
from product_current_scores v
order by v.computed_at desc limit 20;
-- Cross-check one product that was re-scored: view score == MAX(computed_at) row,
-- NOT MAX(score).
```

### Task 2: iOS — trending + recent read the view

**File:** Modify `ios/FoodScanner/PantryService.swift`

- [ ] `loadTrending` (135–190): change `.from("score_results")` (line 147) → `.from("product_current_scores")`. The view is already one-row-per-product, so the `latestScoreByProduct` de-dup loop (155–160) becomes redundant but harmless — **keep the order-by-score-desc** (`.order("score", ascending: false)`, line 150) since the view still needs ranking. Simplify the stale ASSUMPTION doc-comment (123–133) to state the view now guarantees current-score-per-product; delete the "could theoretically still surface" caveat.
- [ ] `loadRecent` (83–89): change `.from("score_results")` → `.from("product_current_scores")`; the `computed_at desc` order + per-product de-dup (96–99) stay correct (harmless with the view) — leave them so a future non-view fallback still works, or simplify to a direct map. Prefer the minimal edit: just swap the table name.
- [ ] Grep gate: `grep -n "product_current_scores\|from(\"score_results\")" ios/FoodScanner/PantryService.swift` → both reads point at the view; no remaining `score_results` history read in the trending/recent paths.
- [ ] (If Chunk 3 shipped) point the swaps ranking query at `product_current_scores` too — see Dependencies note.

> No iOS unit test exists for `PantryService` network reads (they need a live client). Verification is the manual DB cross-check in Task 1 + the on-device "trending shows current score" check in the Exit matrix. Do **not** fabricate a networked test.

---

### Task 3 (TDD): OCR parser — drop the redundant parenthetical orphan

**File:** Modify `supabase/functions/product-ocr/handler.ts`; tests in `supabase/functions/product-ocr/handler_test.ts`.

Problem: `"Colour (E150d)"` → `cleanToken` strips the parenthetical (`handler.ts:93`), leaving a bare display token **"Colour"**, while `E_NUMBER_RE` (75) already captured `en:e150d` from the region. Result: a meaningless "Colour" ingredient row that duplicates the additive. Same for `Flavouring (…)`, `Emulsifier (E322)`, `Preservative (E202)`, etc. — the **function-class word** is noise once the specific additive is captured. Must **not** drop real ingredients that carry an E-number (`"Citric Acid (E330)"` — "Citric Acid" is a genuine ingredient).

- [ ] **Write the failing tests first** (append to `handler_test.ts`):
```ts
Deno.test("parseLabel drops the bare additive-class word when its parenthetical is an additive", () => {
  const parsed = parseLabel("Ingredients: Water, Sugar, Colour (E150d), Salt.");
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(!lower.includes("colour"), "no orphan 'colour' display token");
  assert(!lower.includes("color"));
  assert(parsed.additivesTags.includes("en:e150d"), "additive still captured");
  assert(lower.includes("water") && lower.includes("sugar") && lower.includes("salt"));
});

Deno.test("parseLabel keeps a real ingredient that also carries an E-number", () => {
  const parsed = parseLabel("Ingredients: Water, Citric Acid (E330), Salt.");
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(lower.includes("citric acid"), "citric acid is a real ingredient, kept");
  assert(parsed.additivesTags.includes("en:e330"));
});

Deno.test("parseLabel drops class words for named additive parentheticals too", () => {
  const parsed = parseLabel(
    "Ingredients: Cocoa, Emulsifier (Soya Lecithin - E322), Antioxidant (E306).",
  );
  const lower = parsed.ingredients.map((i) => i.toLowerCase());
  assert(!lower.includes("emulsifier") && !lower.includes("antioxidant"));
  assert(lower.includes("cocoa"));
  assert(parsed.additivesTags.includes("en:e322") && parsed.additivesTags.includes("en:e306"));
});
```
- [ ] Confirm the pre-existing OCR tests still pass unchanged (`handler_test.ts:61-90, 139-167`) — the choco-spread fixture (142) has `Emulsifier (Soya Lecithin - E322)`; after the fix its `ingredients_text` must still contain "Sugar" (155 asserts) but **should no longer list "Emulsifier"**. If line 155 is the only ingredient assertion, add an assertion that "Emulsifier" is absent.
- [ ] **Implement.** Add a curated additive function-class set + an orphan guard, applied in the `parseLabel` ingredient loop (`handler.ts:123-135`) **before** `cleanToken` strips the parens:
```ts
/** OFF/EU function-class words that are label noise once the specific additive
 * in their parenthetical is captured (en:eNNN or a name we resolve). */
const ADDITIVE_CLASS_WORDS = new Set([
  "colour", "color", "colours", "colors", "flavour", "flavor", "flavouring",
  "flavoring", "flavourings", "flavorings", "emulsifier", "emulsifiers",
  "stabiliser", "stabilizer", "stabilisers", "stabilizers", "preservative",
  "preservatives", "antioxidant", "antioxidants", "acidity regulator",
  "acidity regulators", "raising agent", "raising agents", "sweetener",
  "sweeteners", "thickener", "thickeners", "anti-caking agent",
  "firming agent", "humectant", "glazing agent",
]);

/** True when `part` is just an additive-class word whose parenthetical resolves
 * to an additive (E-number or a name in ADDITIVE_NAME_TO_TAG) — a redundant
 * orphan we should NOT emit as a display ingredient. */
function isAdditiveClassOrphan(part: string): boolean {
  const paren = part.match(/^([^()]+?)\s*\(([^)]+)\)\s*$/);
  if (!paren) return false;
  const base = paren[1].trim().toLowerCase().replace(/[.;:*]+$/g, "").trim();
  if (!ADDITIVE_CLASS_WORDS.has(base)) return false;
  const inside = paren[2].toLowerCase();
  if (/\be[\s-]?\d{3,4}[a-z]?\b/.test(inside)) return true;      // E-number inside
  for (const seg of inside.split(/[,;-]+/)) {                    // named additive inside
    if (ADDITIVE_NAME_TO_TAG.has(seg.trim())) return true;
  }
  return false;
}
```
Then in the loop:
```ts
  for (const part of region.split(/[,;]+/)) {
    if (isAdditiveClassOrphan(part)) continue; // additive tag already captured by E_NUMBER_RE / name pass
    const token = cleanToken(part);
    …
```
- [ ] Note the split caveat: `split(/[,;]+/)` breaks `Emulsifier (Soya Lecithin - E322)` correctly (no comma inside), but a parenthetical containing a comma (e.g. `Colour (E150c, E150d)`) would split mid-parens — the orphan guard sees `"Colour (E150c"`, which still matches the E-number test on `E150c`, so the class word is still dropped; the trailing `"E150d)"` fragment `cleanToken`s to noise dropped by the `< 2 chars`/`no-letter` rules or emits a stray token. Add a regression test for `Colour (E150c, E150d)` and, if a stray token appears, tighten `cleanToken` to drop tokens matching `^e\s?\d{3,4}[a-z]?\)?$`. Keep the E-number tag capture intact (both tags land via `E_NUMBER_RE` on the whole region).
- [ ] Run `deno task test` — new + existing OCR tests green.

---

### Task 4 (TDD): Rate-limit `POST /chat` (per-user sliding window)

**Files:** Modify `supabase/functions/chat/handler.ts` + `chat/index.ts`; new migration table; tests in `chat/handler_test.ts`.
**Copy:** COPY_DECK §"Offline & limits": **"You've asked a lot in a short time. Give it a minute and try again."** (line 144) — verbatim.

**Contract:**
- Endpoint unchanged: `POST /functions/v1/chat`, body `{ productId, messages }`.
- New behaviour: per **user id** (JWT `sub`, incl. anon uids), a sliding window of `RATE_LIMIT_MAX` requests per `RATE_LIMIT_WINDOW_MS`. On exceed → **HTTP 429** with header `Retry-After: <seconds>` and body:
```json
{ "error": "rate_limited", "retryAfterSeconds": 42,
  "reply": "You've asked a lot in a short time. Give it a minute and try again.",
  "disclaimer": "Information only — not medical advice." }
```
  (`reply` is populated so the existing iOS chat UI renders the calm line with no client change; `error` lets a future client special-case it.)
- Backward-compatible: if the rate-limit deps are absent (as in current unit tests), the limiter is skipped and behaviour is identical to today.

**Schema (append to the Task-1 migration or a sibling `20260710000100_chat_rate_events.sql`):**
```sql
-- Per-user sliding-window ledger for /chat. Backend-only (service role); no
-- client policies — clients can neither read nor write it (like products writes).
create table chat_rate_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null,
  created_at timestamptz not null default now()
);
create index chat_rate_events_user_ts_idx on chat_rate_events (user_id, created_at desc);
alter table chat_rate_events enable row level security;  -- deny-all to clients
```

- [ ] **Write failing tests first** (`chat/handler_test.ts`). Keep the window math pure and unit-tested:
```ts
// Pure window function.
Deno.test("withinRateLimit allows under the cap, blocks at/over it", () => {
  const now = 1_000_000;
  const win = 60_000, max = 3;
  assertEquals(withinRateLimit([], now, win, max).allowed, true);
  const three = [now - 100, now - 200, now - 300];
  assertEquals(withinRateLimit(three, now, win, max).allowed, false);
  // Timestamps older than the window don't count.
  assertEquals(withinRateLimit([now - 70_000, now - 80_000], now, win, max).allowed, true);
});

Deno.test("withinRateLimit retryAfter = window minus age of oldest in-window hit", () => {
  const now = 1_000_000, win = 60_000, max = 2;
  const r = withinRateLimit([now - 10_000, now - 5_000], now, win, max);
  assertEquals(r.allowed, false);
  assertEquals(r.retryAfterSeconds, 50); // oldest hit ages out in 50s
});

// Handler integration with fake deps.
Deno.test("handleChat returns 429 with calm copy when over the limit", async () => {
  const { deps } = makeDeps({ overLimit: true }); // recentChatRequests returns MAX timestamps
  const res = await handleChat(request({ productId: PRODUCT_ID, messages: [{ role: "user", content: "hi" }] }), deps);
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After") !== null, true);
  const body = await res.json();
  assertEquals(body.error, "rate_limited");
  assertStringIncludes(body.reply, "Give it a minute");
  assertEquals(body.disclaimer, DISCLAIMER);
});

Deno.test("handleChat records the request and proceeds when under the limit", async () => {
  const { deps, state } = makeDeps({ overLimit: false });
  const res = await handleChat(request({ productId: PRODUCT_ID, messages: [{ role: "user", content: "hi" }] }), deps);
  assertEquals(res.status, 200);
  assertEquals(state.recorded.length, 1); // recordChatRequest called once
});
```
  Extend the test's `makeDeps` to add `userId()`, `recentChatRequests(uid)`, `recordChatRequest(uid, ms)` and a `state.recorded` array.
- [ ] **Implement in `handler.ts`.** Add constants + pure function + Deps fields + enforcement:
```ts
export const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute sliding window
export const RATE_LIMIT_MAX = 10;           // requests per user per window (tunable)
export const CHAT_RATE_LIMITED =
  "You've asked a lot in a short time. Give it a minute and try again."; // COPY_DECK

export interface RateDecision { allowed: boolean; retryAfterSeconds: number; }

/** Pure sliding-window check over epoch-ms timestamps. */
export function withinRateLimit(
  timestamps: number[], now: number, windowMs: number, max: number,
): RateDecision {
  const inWindow = timestamps.filter((t) => now - t < windowMs).sort((a, b) => a - b);
  if (inWindow.length < max) return { allowed: true, retryAfterSeconds: 0 };
  const oldest = inWindow[0];
  const retryAfterSeconds = Math.max(1, Math.ceil((windowMs - (now - oldest)) / 1000));
  return { allowed: false, retryAfterSeconds };
}
```
  Add to `Deps` (all optional → backward compatible):
```ts
  userId?(): string | null;                               // JWT sub (anon uid ok)
  recentChatRequests?(userId: string): Promise<number[]>; // epoch-ms in window, service role
  recordChatRequest?(userId: string, atMs: number): Promise<void>;
```
  In `handleChat`, after the `Authorization` 401 check (`handler.ts:417-419`) and before parsing the body, enforce:
```ts
  const uid = deps.userId?.() ?? null;
  if (uid && deps.recentChatRequests && deps.recordChatRequest) {
    const now = deps.now();
    const recent = await deps.recentChatRequests(uid);
    const decision = withinRateLimit(recent, now, RATE_LIMIT_WINDOW_MS, RATE_LIMIT_MAX);
    if (!decision.allowed) {
      return new Response(
        JSON.stringify({ error: "rate_limited", retryAfterSeconds: decision.retryAfterSeconds,
          reply: CHAT_RATE_LIMITED, disclaimer: DISCLAIMER }),
        { status: 429, headers: { ...CORS_HEADERS, "Content-Type": "application/json",
          "Retry-After": String(decision.retryAfterSeconds) } },
      );
    }
    await deps.recordChatRequest(uid, now);
  }
```
  (Record on *accepted* requests only — a 429'd request must not extend its own window.)
- [ ] **Wire `chat/index.ts`.** Decode the JWT `sub` and implement the ledger deps against the service-role client:
```ts
function jwtSub(req: Request): string | null {
  const auth = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!auth) return null;
  try {
    const payload = JSON.parse(atob(auth.split(".")[1] ?? ""));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch { return null; }
}
// in buildDeps(req):
  userId: () => jwtSub(req),
  async recentChatRequests(userId) {
    const since = new Date(Date.now() - 60_000).toISOString();
    const { data } = await supabase.from("chat_rate_events")
      .select("created_at").eq("user_id", userId).gte("created_at", since);
    return (data ?? []).map((r) => Date.parse(r.created_at as string));
  },
  async recordChatRequest(userId) {
    await supabase.from("chat_rate_events").insert({ user_id: userId });
  },
```
  (Window constant duplicated here is fine; the authoritative math is the pure `withinRateLimit`. Optionally prune rows older than the window opportunistically in `recordChatRequest`.)
- [ ] **Deploy + test:** `supabase functions deploy chat --project-ref usmdthxnxzdywtjgbokl`. Burst test with a valid anon JWT:
```bash
for i in $(seq 1 12); do curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "$SUPABASE_URL/functions/v1/chat" -H "Authorization: Bearer $ANON_JWT" \
  -H "Content-Type: application/json" \
  -d '{"productId":"<real-uuid>","messages":[{"role":"user","content":"hi"}]}'; done
# Expect 200 up to the cap, then 429 with Retry-After.
```

---

### Task 5 (TDD): Re-score cron on `score_version` bump

**New files:** `supabase/functions/rescore/{index.ts, handler.ts, handler_test.ts}`; schedule in the Task-1 migration (or `20260710000200_rescore_cron.sql`).

Reuses: `computeScore` + `SCORE_VERSION` (`engine.ts:19`), `mapAdditiveTiers` + `appendUnknownAdditivesNote` (`product/handler.ts:124-160`), `mapOffPayload` (`off.ts:59`). No new scoring math.

**Contract:** `POST /functions/v1/rescore` (service-role/cron-only — see auth note).
- Finds products whose **current** `product_current_scores.score_version != SCORE_VERSION` (batched, `limit` param, default e.g. 50).
- For each: reconstruct score inputs — `source === "off"` → `mapOffPayload(raw_off)` → `{novaGroup, nutriscoreGrade, additivesTags}`; `source === "ocr"` → read `raw_off.parsed.additivesTags` (novaGroup/nutriscore null → band stays `unknown`). Then `mapAdditiveTiers` → `computeScore` → **insert a new `score_results` row** (history preserved; the view then returns it).
- `?dryRun=1` → returns the list of product ids + counts that *would* be re-scored, inserts nothing.
- Response: `{ scanned, rescored, dryRun, products: [{ id, from, to }] }`.

- [ ] **Write failing tests first** (`rescore/handler_test.ts`, fake deps — no DB/network):
```ts
Deno.test("rescore selects only products whose current score_version is stale", async () => {
  const { deps, state } = makeDeps({ stale: [offProductAtVersion("1.0.0")], current: [offProductAtVersion(SCORE_VERSION)] });
  const res = await handleRescore(request({}), deps);
  assertEquals(res.status, 200);
  assertEquals(state.inserted.length, 1); // only the stale one re-scored
});
Deno.test("rescore dryRun inserts nothing but reports the stale product", async () => {
  const { deps, state } = makeDeps({ stale: [offProductAtVersion("1.0.0")] });
  const res = await handleRescore(request({}, { query: "?dryRun=1" }), deps);
  const body = await res.json();
  assertEquals(body.dryRun, true);
  assertEquals(body.products.length, 1);
  assertEquals(state.inserted.length, 0);
});
Deno.test("rescore recomputes an OFF product deterministically from raw_off", async () => {
  const { deps, state } = makeDeps({ stale: [offProductAtVersion("1.0.0")] });
  await handleRescore(request({}), deps);
  assertEquals(state.inserted[0].score_version, SCORE_VERSION);
  assertEquals(typeof state.inserted[0].score, "number"); // real number, not null, for an OFF product
});
Deno.test("rescore keeps an OCR product at band unknown (no NOVA/Nutri-Score)", async () => {
  const { deps, state } = makeDeps({ stale: [ocrProductAtVersion("1.0.0")] });
  await handleRescore(request({}), deps);
  assertEquals(state.inserted[0].band, "unknown");
});
Deno.test("rescore is a no-op when everything is current", async () => {
  const { deps, state } = makeDeps({ current: [offProductAtVersion(SCORE_VERSION)] });
  await handleRescore(request({}), deps);
  assertEquals(state.inserted.length, 0);
});
```
- [ ] **Implement `handler.ts`** — pure `handleRescore(req, deps)` with `Deps.findStaleProducts(currentVersion, limit)` (returns `{ id, source, raw_off }[]` for products whose current score_version ≠ currentVersion), `Deps.insertScoreResult(productId, ScoreOutput)`, `Deps.now()`. Derive inputs per source, call the shared engine, insert. Guard: skip products whose `raw_off` can't be mapped (log-and-continue, count as skipped) so one bad payload never aborts the batch.
- [ ] **Implement `index.ts`** — service-role client; `findStaleProducts` via a query joining `products` to `product_current_scores` (`where score_version is distinct from SCORE_VERSION`, plus products with no score row at all). Deploy name `rescore`.
- [ ] **Auth note:** this function must NOT be publicly triggerable. Deploy with `--no-verify-jwt` **off** is not enough (anon JWTs pass). Require a shared secret header checked in `index.ts` (`X-Rescore-Secret` == `Deno.env.get("RESCORE_SECRET")`) → 401 otherwise. The cron passes it. Add `RESCORE_SECRET` to the function secrets (STATE.md secrets list) — keep it out of the repo.
- [ ] **Schedule via `pg_cron` + `pg_net`** (migration):
```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;
-- Daily at 04:00 UTC: fire the rescore function. Batches; re-runs next day until drained.
select cron.schedule('rescore-on-version-bump', '0 4 * * *', $$
  select net.http_post(
    url := 'https://usmdthxnxzdywtjgbokl.functions.supabase.co/rescore',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Rescore-Secret', current_setting('app.rescore_secret', true)),
    body := jsonb_build_object('limit', 200)
  );
$$);
```
  (Set `app.rescore_secret` via `alter database … set` or inline the secret through a Vault reference — document the chosen mechanism in the migration comment; never commit the literal.)
- [ ] **Deploy + dry-run test (Exit criterion):** deploy the function, then temporarily point one cached product's current row at an old `score_version` (or bump `SCORE_VERSION` on a branch), and call `POST /rescore?dryRun=1` with the secret → confirm it reports that product; call without `dryRun` → confirm a fresh `score_results` row at `SCORE_VERSION` appears and `product_current_scores` now returns it.

---

### Task 6: Dietitian weight review export (no code change unless weights change)

**New file:** `docs/reviews/SCORE_WEIGHTS_REVIEW_2026-07.md` (+ optional `.csv`). **No app/backend code changes.**

- [ ] Export the live tuning surface for the founder's dietitian reviewer, sourced from `_shared/scoring/weights.json`, `additives_risk.json`, and `calibration.json`:
  - Composite weights: processing **0.50**, nutrition **0.35**, additives **0.15** (`weights.json:2-6`; SCORING_METHODOLOGY §4).
  - NOVA→processing map (1→100, 2→80, 3→55, 4→20) and Nutri→nutrition map (a→90…e→12).
  - Additive penalty tiers (low/moderate/higher, first vs additional).
  - The 50-product calibration table: input → expected `{processing, nutrition, additives, score, band}` with the `notes` rationale (`calibration.json`), plus a column for the reviewer to mark agree/disagree.
  - Current `score_version` = **1.1.0** (`engine.ts:19`), so the reviewer knows what version they're signing off.
- [ ] Add a one-line reviewer sign-off block + a "STANDING INSTRUCTION" note: **if the reviewer changes any weight or additive tier → bump `SCORE_VERSION` in `engine.ts:19`, log it in `MEMORY.md` (SCORING_METHODOLOGY §8), and the Task-5 cron auto-re-scores every cached product on its next run.** No other code touches.
- [ ] This task's "exit" is: sheet generated + flagged for the founder's reviewer. It does not block the chunk's technical gates.

---

## Verification / Exit criteria

**Chunk exit (from MASTER_PLAN §Chunk 4):**
- [ ] **Trending shows current scores** — verified on device against `score_results` history: a product with an old high + newer lower row shows the *newer* score in Trending (Task 1 SQL cross-check + on-device look).
- [ ] **OCR regression tests green** — `"Colour (E150d)"` and friends produce no orphan class-word ingredient, additive tag still captured (Task 3).
- [ ] **Chat returns 429 under burst** — 12-request burst hits the cap → 429 with `Retry-After` + the COPY_DECK calm line (Task 4).
- [ ] **Cron dry-run re-scores a stale product** — `POST /rescore?dryRun=1` reports it; real run inserts a current-version `score_results` row (Task 5).

**Standard gate (MASTER_PLAN §Standing rules):**
- [ ] `cd supabase/functions && deno task test` — **all green, 121 + new tests** (OCR ×3–4, rate-limit ×4, rescore ×5); `deno fmt` + `deno lint` clean.
- [ ] `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build` — succeeds; `xcodebuild test -only-testing:FoodScannerTests` green.
- [ ] **6-shot screenshot matrix** — Home (Trending row is the only UI-visible change this chunk): SE-proxy (**iPhone 17e**, per Chunk 0 substitution) / iPhone 17 Pro / 17 Pro Max × **default + XXL (AX5)** Dynamic Type. No clipping; Trending cards render current scores.
- [ ] **Device install** — trending/recent verified against the live Supabase project; chat 429 verified from the device (burst), calm copy renders in the chat sheet.
- [ ] **Principles gate:** transparent scoring (current not highest-ever), ED-safe/calm copy (429 line is non-blaming), honest states, never-a-dead-end (429 tells the user exactly what to do), **LLM-never-does-math** (re-score is the deterministic engine), AA a11y.
- [ ] **Teardown-AVOID gate** (`design-teardown.md` §Master AVOID) — no new UI surface violates #6 (raw floats — scores stay integer), #2 (unsourced numbers — unchanged), #1 (no alarm-red). The 429 copy uses no banned words.
- [ ] **ui-ux-pro-max Pre-Delivery Checklist** run on the Trending row (icons, contrast, layout, a11y) — pass. Query first: `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "rate limit error state" --domain ux`.
- [ ] **RLS re-check:** anon/authenticated clients can `select` `product_current_scores` but cannot write it or `chat_rate_events`; `score_results` writes still service-role only.
- [ ] **Wrap-up:** `MEMORY.md` decision entry (view + rate-limit + rescore cron + parser fix; note if `SCORE_VERSION` bumped) + `STATE.md` status-line update ("Chunk 4 DONE").

---

## Notes for the executor
- The only user-visible UI change is Trending/Recent now reflecting current scores — the screenshot matrix is light. The bulk of the risk is backend correctness (view semantics, sliding-window edges, cron auth), which is why every pure function is TDD'd offline.
- Do **not** expose `chat_rate_events` or `RESCORE_SECRET` to the client. Keys stay out of the repo (STATE.md standing warning; rotate before Chunk 7).
- If Chunk 3 (swaps) or Chunk 2 (search) are not yet built, still ship the view + trending/recent wiring, and leave the one-line "read `product_current_scores`" note in those plans so they wire it when they land.
