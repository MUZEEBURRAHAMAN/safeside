# Backend Spec

**Version:** 1.0 (draft for build) · June 2026
**Role:** iOS is a thin client. The backend owns all keys, the scoring engine, data ingestion/caching, and the AI routes. This spec closes the biggest structural gap: *where things run and how data flows.*
**Reads with:** `DATA_MODEL.md`, `SCORING_METHODOLOGY.md`, `API_INTEGRATION.md`, `AI_INGREDIENT_EXPLANATION.md`.

---

## 1. Decision: what runs where

| Concern | Where | Why |
|---|---|---|
| Auth + Postgres + storage | **Supabase** | Managed, has `supabase-swift`, RLS, anonymous auth. Least ops for a solo founder. |
| Product lookup, scoring, swaps | **Supabase Edge Functions (TypeScript/Deno)** | Co-located with the DB, cheap, scales to zero. Fine for CRUD + deterministic scoring. |
| AI routes (ingredient explain, chat) | **Edge Function → LLM provider** | Keeps keys server-side; thin proxy + RAG assembly. |
| Diet optimizer (OR-Tools/PuLP) | **Deferred** (not in MVP) | Was for the meal planner, which the MVP cut. Add a small Python service only when the planner returns. |
| Data ingestion (OFF/USDA cache) | **Scheduled job** (Supabase cron / GitHub Action) | Warms and refreshes the product cache. |

**Principle:** start with Supabase-only (Edge Functions). Introduce a separate service (Node/Bun or Python) *only* if a need appears (heavy compute, the optimizer). Don't build microservices for an MVP.

---

## 2. The product-data pipeline (first thing to build)

The calibration proved: scoring is only as good as the real data feeding it. Build this first.

**On scan (`GET /product/:barcode`):**
1. Look up `products` cache by barcode.
2. **Cache hit** & `fetched_at` within TTL (30 days) & current `score_version` → return cached product + score.
3. **Miss / stale** → fetch **Open Food Facts** `GET /api/v2/product/{barcode}.json` (fields filtered), with the required descriptive **User-Agent**. Map to our `Product` shape.
4. Enrich nutrients from **USDA FoodData Central** where OFF is thin (match by name/category; USDA is public domain).
5. Compute the score (§3), upsert `products` + `score_results`, return.
6. **Not found in OFF** → respond `needs_ocr`; client sends the label to `POST /product/ocr` (parsed text → provisional product, `source=ocr`, `confidence=limited`).

**Storage:** keep `raw_off` JSON so scores can be recomputed when `score_version` changes without re-fetching. Store `fetched_at`, `data_confidence`.

**Refresh job (cron, low priority):** re-fetch popular/ stale products; re-score all when `score_version` increments.

**Rate/limits:** be polite to OFF (cache hard, batch, backoff). USDA key ~1,000 req/hr — cache. Never call external APIs on a cache hit.

---

## 3. Scoring service

- Pure function `computeScore(product) -> {score, band, breakdown, confidence, score_version}` implementing `SCORING_METHODOLOGY.md`. **Deterministic, in code — never the LLM.**
- Lives in a shared module called by the product endpoint. Unit-tested against the calibration set (`docs/Scoring_Calibration.xlsx`).
- Versioned: bump `score_version` when weights/additive table change; refresh job re-scores.

---

## 4. Endpoints (MVP surface)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/product/:barcode` | anon JWT | lookup → cache → score |
| POST | `/product/ocr` | anon JWT | label text → provisional scored product |
| POST | `/product/:id/report` | anon JWT | user flags wrong/missing data |
| GET | `/product/:id/ingredients` | anon JWT | AI ingredient explanations (see AI spec; cached) |
| POST | `/chat` | anon JWT | grounded product Q&A (Phase 3) |
| GET | `/search?q=` | anon JWT | product/ingredient/brand search |
| GET/POST/DELETE | `/pantry` | anon JWT | pantry CRUD |

All calls carry the Supabase JWT (anonymous or linked). **RLS** enforces per-user ownership on pantry/profile; `products`/`score_results`/ingredient explanations are global cache, written only by the backend.

---

## 5. Secrets, cost & observability
- **Secrets** (OFF UA, USDA key, LLM key) in Supabase secrets / env. Never in the app bundle.
- **Cost control (LLM is the variable cost):** cache ingredient explanations per ingredient (they rarely change) and per-product summaries; rate-limit `/chat` and AI endpoints per user; cap tokens. Most scans should cost $0 in AI (deterministic score + cached explanations).
- **Observability:** log external-API latency/failures, cache hit-rate, AI token cost per endpoint; alert on OFF/USDA/LLM error spikes. Sentry (client) + function logs.

---

## 6. Environments & CI
- `dev` and `prod` Supabase projects. Migrations in version control (Supabase CLI). Edge Functions deployed via CLI / GitHub Action.
- Seed `dev` with the calibration products so the app has data on day one.

## 7. Build order (backend)
1. Postgres schema (`DATA_MODEL.md`) + RLS + anonymous auth.
2. `GET /product/:barcode` with OFF fetch + cache + scoring (the spine).
3. USDA enrichment + OCR endpoint.
4. Pantry CRUD.
5. Ingredient-explanation endpoint (see AI spec) with caching.
6. Search; then (Phase 3) chat.

## 8. Open decisions
- Edge Functions (Deno/TS) vs a small Node service — start with Edge Functions; revisit if compute grows.
- Whether to pre-ingest a base catalog (e.g. top N OFF products for the launch region) vs. purely on-demand caching. Recommendation: pre-warm a few thousand common regional products for a fast first experience.
