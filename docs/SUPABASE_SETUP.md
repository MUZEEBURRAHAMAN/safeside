# Supabase Integration — Full Setup Steps

**Version:** 1.0 · July 2026
**Goal:** connect the code that already exists (`supabase/` functions + migration, iOS `AppConfig`/`Config.xcconfig`, `supabase-swift` in `project.yml`) to a real Supabase project, and get one real scan returning a scored product end-to-end.
**Reads with:** `docs/BACKEND_SPEC.md`, `supabase/README.md`, `ios/README.md`.

> What's already done in the repo (don't rebuild): the Postgres schema + RLS (`supabase/migrations/…initial_schema.sql`), the deterministic scoring engine + fixtures (`supabase/functions/_shared/scoring/`), the `GET /product/:barcode` function (`supabase/functions/product/`), the OFF client (`_shared/off.ts`), and the iOS side (`SessionService` = anonymous auth, `APIClient` = calls `functions/v1`, `AppConfig` = reads config from Info.plist). You are *connecting* these, not writing them.

---

## Prereqheck (once)
```sh
supabase --version   # CLI (2.10x ok)
deno --version       # for function tests
xcodegen --version   # generates the Xcode project
```
Install any missing: `brew install supabase/tap/supabase deno xcodegen`.

---

## Step 1 — Create the cloud project
1. supabase.com → **New project**. Pick a region near your launch market (OFF coverage + latency).
2. Save the DB password.
3. From **Project Settings → API**, copy:
   - **Project URL** → `https://YOUR-REF.supabase.co`
   - **anon / publishable key** (safe to ship in the app)
   - (leave the **service_role** key alone — it's for functions only, platform-injected; never in the app)
4. **Authentication → Providers/Settings → enable "Anonymous sign-ins."** Required — the app gets a JWT before any account exists (guest-first). This mirrors `auth.enable_anonymous_sign_ins = true` already in `supabase/config.toml`.

---

## Step 2 — Configure the iOS app
```sh
cd ios
cp Config-example.xcconfig Config.xcconfig     # Config.xcconfig is gitignored — never commit real keys
```
Edit `ios/Config.xcconfig`:
```
SUPABASE_URL = https:/$()/YOUR-REF.supabase.co     # keep the $() — xcconfig treats // as a comment
SUPABASE_ANON_KEY = <your anon key>
DEVELOPMENT_TEAM = <your Apple Team ID>            # needed for device builds
```
Then regenerate the project:
```sh
xcodegen generate
```
`supabase-swift` is already declared in `project.yml` (Xcode resolves it on open). `AppConfig` reads these values from the Info.plist at runtime; if they're still placeholders, `isConfigured` is false and the app degrades gracefully instead of crashing.

---

## Step 3 — Link the repo & apply the schema
```sh
supabase link --project-ref YOUR-REF     # asks for the DB password
supabase db push                          # applies migrations/…initial_schema.sql (tables + RLS + enums)
```
Verify in the dashboard (**Table editor**): `profiles, products, score_results, pantry_items, events` exist, and RLS is on.

---

## Step 4 — Test the scoring engine (no network, no DB)
```sh
cd supabase/functions
deno task test        # all 50 calibration products must match exactly
```
This is the trust gate — the engine must reproduce `docs/Scoring_Calibration.xlsx` before you deploy.

---

## Step 5 — Deploy the function
```sh
supabase functions deploy product
```
Secrets: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically — nothing to set yet. When USDA enrichment / the AI route land:
```sh
supabase secrets set USDA_API_KEY=... LLM_API_KEY=...
```

---

## Step 6 — Smoke-test the backend directly
```sh
curl -s "https://YOUR-REF.supabase.co/functions/v1/product/737628064502" \
  -H "apikey: <anon key>" -H "Authorization: Bearer <anon key>" | jq
```
Expect a JSON product with a `score`, `band`, and `factors`. A first-time barcode is a cache miss → it fetches OFF, scores, stores; scan the same barcode again → served from Postgres (faster).

---

## Step 7 — Run the app end-to-end
```sh
cd ios && xcodegen generate && open FoodScanner.xcodeproj
```
Build on a **real iPhone** (the Simulator has no camera). On launch: `SessionService` creates an **anonymous** Supabase session (guest-first, no login). Scan a real barcode → `APIClient` calls `/product/:barcode` → the scored `ProductView` renders. Not found → the calm "snap the label" (OCR) state.

---

## Step 8 — Local dev loop (optional but recommended)
Iterate without touching the cloud:
```sh
supabase start                 # local Postgres + Auth + Functions (Docker)
supabase functions serve product
# point ios/Config.xcconfig SUPABASE_URL at the local URL supabase prints, then xcodegen generate
```
`supabase db reset` re-applies migrations locally.

---

## Step 9 — Environments (dev vs prod)
- Create a **second** Supabase project for `prod`; keep `dev` for daily work.
- Swap by editing `Config.xcconfig` (or keep two: `Config-dev.xcconfig` / `Config-prod.xcconfig` and point `configFiles` per build config in `project.yml`).
- Pre-warm a few thousand common regional products in each so first scans are instant (`BACKEND_SPEC.md` §8).

---

## Security & git hygiene (already handled — verify)
- `ios/Config.xcconfig` is **gitignored**; only `Config-example.xcconfig` is tracked. Confirm: `git check-ignore ios/Config.xcconfig`.
- The **anon key** is publishable-tier (fine in the binary); the **service_role** key lives only in Edge Functions (platform-injected) and never in the app or repo.
- RLS restricts `profiles`/`pantry_items`/`events` to the owning user; `products`/`score_results` are global cache, written only by the service-role function.

---

## Troubleshooting
| Symptom | Cause / fix |
|---|---|
| App shows "not connected to a backend" | `Config.xcconfig` still has placeholders, or you didn't re-run `xcodegen generate` after editing it. |
| `SUPABASE_URL` truncated / nil | The `//` in the URL was treated as a comment — keep the `$()` escape (`https:/$()/…`). |
| Anonymous sign-in fails | "Anonymous sign-ins" not enabled in the dashboard (Step 1.4). |
| Function 500s | Check `supabase functions logs product`; confirm `db push` ran and OFF User-Agent is set in `_shared/off.ts`. |
| Scores look wrong | Re-run `deno task test`; the engine must match the calibration set before trusting output. |

## Bottom line
Steps 1–3 connect the project; 4 proves the engine; 5–7 get a live scan scored end-to-end. After that, the next backend features (OCR endpoint, ingredient explanations) follow the same pattern: add a function under `supabase/functions/`, test with Deno, `supabase functions deploy`.
