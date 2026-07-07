# Supabase backend

The backend spine for the food scanner: Postgres schema (+ RLS), the deterministic
scoring engine, and the `GET /product/:barcode` Edge Function. See
`docs/BACKEND_SPEC.md`, `docs/DATA_MODEL.md`, and `docs/SCORING_METHODOLOGY.md`.

## Layout

```
supabase/
  config.toml                          # CLI config (anonymous sign-ins enabled)
  migrations/
    20260707000000_initial_schema.sql  # profiles, products, score_results, pantry_items, events + RLS
  functions/
    deno.json                          # test task + imports
    _shared/
      off.ts                           # Open Food Facts v2 client (User-Agent, field filter)
      scoring/
        engine.ts                      # pure computeScore() — score_version 1.0.0
        weights.json                   # composite weights + mappings (data, not code)
        additives_risk.json            # curated additive risk table v1.0 (regulatory sources)
        calibration.json               # 50-product calibration set (from docs/Scoring_Calibration.xlsx)
    product/
      index.ts                         # Deno.serve wiring (supabase-js, service role)
      handler.ts                       # pure handler — cache → OFF → score → upsert
```

## Tests

No network, no DB. All 50 calibration products must match exactly.

```sh
cd supabase/functions
deno task test
```

## Deploy (later, once a Supabase project exists)

```sh
# 1. Link the local repo to the project (replaces the "foodscanner" placeholder id)
supabase link --project-ref <project-ref>

# 2. Apply the schema
supabase db push

# 3. Deploy the product function
supabase functions deploy product

# 4. Secrets — none needed yet beyond the platform-injected ones.
#    SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically to
#    Edge Functions. When USDA enrichment / the AI route land:
supabase secrets set USDA_API_KEY=... LLM_API_KEY=...
```

Enable **anonymous sign-ins** in the project's Auth settings (mirrors
`auth.enable_anonymous_sign_ins = true` in `config.toml`) so the iOS client can
get a JWT before any account exists.

## Invariants worth knowing

- `score_version` is `1.0.0` (`engine.ts`). Bump it whenever `weights.json` or
  `additives_risk.json` change; the cache treats older versions as stale and
  rescoring happens on next fetch. Log changes in `MEMORY.md`.
- `products` / `score_results` are a global cache: readable by any signed-in
  (incl. anonymous) session, writable only via the service role. Everything
  user-owned is RLS'd to `auth.uid()`.
- The response of `/product/:barcode` must decode into
  `ios/FoodScanner/Models.swift` — when a product has neither NOVA nor
  Nutri-Score, the `score` object is omitted entirely (band "unknown").
- Additives not in `additives_risk.json` score as low tier and are flagged
  "not yet reviewed" — absence of review is never treated as concern.
- Open Food Facts data is ODbL: keep the attribution in factor sources, and
  share-alike applies to the data.
