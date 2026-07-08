# Supabase backend

The backend spine for the food scanner: Postgres schema (+ RLS), the deterministic
scoring engine, the product/OCR Edge Functions, and the AI ingredient-explanation
endpoint. See `docs/BACKEND_SPEC.md`, `docs/DATA_MODEL.md`,
`docs/SCORING_METHODOLOGY.md`, and `docs/AI_INGREDIENT_EXPLANATION.md`.

## Endpoints

| Method | Client path | Function | Purpose |
|---|---|---|---|
| GET | `/product/:barcode` | `product` | barcode → cache → OFF → score |
| POST | `/product/ocr` | `product-ocr` | on-device OCR label text → provisional (limited) product |
| GET | `/product/:id/ingredients` | `ingredients` | AI ingredient explanations (retrieval-not-generation, cached) |
| POST | `/chat` | `chat` | grounded product Q&A (Phase 3) — answers about ONE product, from its data only |

Edge Function names can't contain slashes, so the OCR and ingredient functions
deploy as `product-ocr` and `ingredients`. The `ingredients` handler accepts both
`/ingredients/:id` and `/product/:id/ingredients` (and `?id=`); route the friendly
client paths at the edge/gateway if desired. The `chat` function has no slash, so
its client path is simply `POST /functions/v1/chat`.

## Layout

```
supabase/
  config.toml                          # CLI config (anonymous sign-ins enabled)
  migrations/
    20260707000000_initial_schema.sql  # profiles, products, score_results, pantry_items, events + RLS
    20260708000000_ingredient_kb.sql   # ingredient_kb + ingredient_explanations cache + RLS
    20260708120000_kb_seed_v1_1.sql    # GENERATED — upserts the full KB seed (v1.1, 174 entries) into ingredient_kb
  tools/
    build_kb_seed.py                    # regenerates the KB seed + SQL upsert from additives_risk.json (stdlib; --check verifies sync)
  functions/
    deno.json                          # test task + imports
    _shared/
      off.ts                           # Open Food Facts v2 client (User-Agent, field filter)
      usda.ts                          # USDA FoodData Central client — nutrient enrichment (fuzzy name match, gap-fill)
      llm.ts                           # provider-agnostic OpenAI-compatible LLM client (injectable; null when no key)
      kb/
        kb.ts                          # KB types + guardrails + bounded LLM rewrite (pure, offline-testable)
        ingredient_kb_seed.json        # GENERATED — do not hand-edit; run tools/build_kb_seed.py
      scoring/
        engine.ts                      # pure computeScore() — score_version 1.1.0
        weights.json                   # composite weights + mappings (data, not code)
        additives_risk.json            # curated additive risk table v1.1 — 124 E-numbers (regulatory sources)
        calibration.json               # 50-product calibration set (from docs/Scoring_Calibration.xlsx)
    product/
      index.ts                         # Deno.serve wiring (supabase-js, service role)
      handler.ts                       # pure handler — cache → OFF → score → upsert
    product-ocr/
      index.ts                         # Deno.serve wiring (service role; inserts provisional product)
      handler.ts                       # pure handler — label text → parse → engine (unknown/limited) → create
    ingredients/
      index.ts                         # Deno.serve wiring (service role + LLM client from env)
      handler.ts                       # pure handler — resolve KB → cache → rewrite → { ingredients: [...] }
    chat/
      index.ts                         # Deno.serve wiring (service role for product/score/KB; user-scoped client for the profile)
      handler.ts                       # pure handler — assemble grounding context → bounded prompt → guarded reply → { reply, sources, disclaimer }
```

## Nutrient enrichment (USDA FoodData Central)

Open Food Facts nutrient tables are often thin. On a cache **miss/stale re-fetch**
only (never on a cache hit), when OFF is missing key macros the `product` handler
enriches from **USDA FDC** (`_shared/usda.ts`) by fuzzy name/brand match and
**merges**: OFF always wins where present, USDA fills the gaps. The merged row
records provenance under `nutrients._enrichment` (`{ source: "usda", fdcId,
description, dataType, fields }`). USDA is best-effort — no key, no match, or any
error returns `null` and the scan still succeeds on OFF data alone. USDA data is
public domain (CC0), so no attribution is required. The numeric **score is
unaffected** (it derives from NOVA + Nutri-Score + additives); enrichment only
improves the stored nutrient table. Set `USDA_API_KEY` (below); tests fall back to
`DEMO_KEY` but never hit the network (fetch is injected).

## Ingredient knowledge base (the AI feature)

`ingredient_kb` is the curated, versioned source of truth (`kb_version` 1.1 — 174
entries: 124 additives + 50 common/base ingredients). The
`/product/:id/ingredients` endpoint RETRIEVES vetted facts and the LLM only
REWRITES them — it never generates facts (docs/AI_INGREDIENT_EXPLANATION.md).
Guardrails enforced in code (`_shared/kb/kb.ts`), all unit-tested offline:

- **No KB entry → no explanation** — returns the "We don't have vetted info on
  this ingredient yet" limited state. The LLM is never called for unknowns.
- **No fabrication** — a missing KB field stays `null` ("limited") in the output
  regardless of what the LLM returns.
- **Risk consistency** — the displayed `riskTier` always equals the KB/scoring
  tier; the LLM can't change it. The KB additive tiers are identical to
  `scoring/additives_risk.json` (a seed-integrity test enforces this).
- **Banned-word filter** — any fear word in a rewrite discards it and falls back
  to the raw (vetted) KB text.
- **Graceful degradation** — no `LLM_API_KEY` → raw KB fields served verbatim
  (still sourced, still no fabrication). Rewrites are cached in
  `ingredient_explanations` by `(ingredient_id, kb_version, locale)`, so most
  scans cost ~$0 in AI.

Regenerate / verify the seed (writes BOTH the JSON seed and the SQL upsert):

```sh
python3 supabase/tools/build_kb_seed.py           # regenerate after editing additives_risk.json or the script
python3 supabase/tools/build_kb_seed.py --check    # CI-friendly: exit 1 if the seed OR SQL is stale
```

Seeding the DB (main session): apply the generated migration
`migrations/20260708120000_kb_seed_v1_1.sql` (an idempotent `insert … on conflict
(id) do update`) after the table-creating migration — e.g. `supabase db push`, or
paste it into the SQL editor. It upserts all 174 entries with the service role.
(Alternatively, load `_shared/kb/ingredient_kb_seed.json`'s `entries` array.)
Bumping content → bump `KB_VERSION` in **both** `_shared/kb/kb.ts` and
`tools/build_kb_seed.py` (`KB_VERSION` constant), then regenerate — this refreshes
every seed row's `kb_version` and invalidates cached rewrites.

## Grounded AI chat (the `chat` endpoint)

`POST /chat` answers a user's questions about **one specific scanned product**
("Is this safe?", "Can my kid eat this?", "Why this score?", "Better
alternatives?") — grounded ONLY in that product's real data, never free-floating
medical advice. It reuses the ingredient endpoint's philosophy: the LLM
re-phrases facts we already hold, it does not generate them.

Request body: `{ "productId": "<uuid>", "messages": [{ "role": "user"|"assistant", "content": "..." }] }`

Response (CONTRACT — iOS depends on it exactly):

```json
{
  "reply": "<assistant text>",
  "sources": [ { "name": "string", "url": "string|null" } ],
  "disclaimer": "Information only — not medical advice."
}
```

**How the grounding context is built** (server-side, by `productId`):

- the **product** (name/brand/nutrients/NOVA/Nutri-Score/additives/allergens),
- its latest **`score_results` breakdown** (sub-scores + weights + the
  plain-language factor details + sources),
- the matching **`ingredient_kb` entries** for its additives/ingredients
  (resolved by reusing the `ingredients` endpoint's `buildCandidates` — unknown
  ingredients contribute **no** facts, so the model can't invent them),
- optionally the caller's **profile** (allergies / health flags / diet),
  read under RLS with a user-scoped client (their JWT); any problem → skipped.

The context is serialized into a strict bounded **system prompt**, followed by
the (bounded) conversation history as real user/assistant turns.

**Guardrails (ship-blocking, mirror the ingredients endpoint):**

- **Grounded only** — the prompt orders the model to answer from the provided
  data and to say it doesn't have the info otherwise; never outside knowledge.
- **Not medical advice** — never diagnose/prescribe/"safe for your condition";
  for "can my kid/pregnant/diabetic eat this" it states the factual data (which
  additives + reviewed tier, which allergens) plus "general information, not
  medical advice; check with a professional". The `disclaimer` is **always**
  returned.
- **Banned-word filter** — the reused `hasBannedWord` (from `_shared/kb/kb.ts`)
  runs on the model output; any fear word discards it for a neutral canned reply.
- **Sources are deterministic** — built from the score factors + resolved KB
  entries (deduped), never from the model, so a citation/URL can't be fabricated.
- **Graceful degradation** — no `LLM_API_KEY` (or any LLM error / unparsable
  output) → a canned "AI chat is unavailable right now" reply; never crashes.
- **Bounded cost** — output tokens capped (`max_tokens`), history trimmed to the
  last ~8 turns, each message length-capped.

Env vars are the same `LLM_*` set as the ingredient endpoint (below); `chat`
additionally uses `SUPABASE_ANON_KEY` (platform-injected) for the user-scoped
profile read.

## Tests

No network, no DB (the LLM + fetch are mocked). All 50 calibration products must
match exactly, and the AI guardrail suites — ingredient (no-hallucination,
banned-language, risk-consistency, unknown-ingredient, missing-LLM-key) and chat
(grounded prompt assembly, banned-word/no-medical-advice, no-fabrication,
missing-key graceful reply, 404 + validation) — plus OCR parsing, KB-seed
integrity, USDA mapping/merge, and product-handler enrichment all pass
(121 tests).

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

# 3. Deploy the functions
supabase functions deploy product
supabase functions deploy product-ocr
supabase functions deploy ingredients
supabase functions deploy chat

# 4. Seed the ingredient KB (service role) from _shared/kb/ingredient_kb_seed.json.

# 5. Secrets. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected
#    automatically. The AI ingredient endpoint reads (all optional — absent
#    LLM_API_KEY makes it serve raw vetted KB text, no rewrite):
supabase secrets set LLM_API_KEY=...            # enables the LLM rewrite
supabase secrets set LLM_BASE_URL=...           # default https://api.groq.com/openai/v1
supabase secrets set LLM_MODEL=...              # default llama-3.3-70b-versatile
supabase secrets set USDA_API_KEY=...           # USDA FDC nutrient enrichment (free key: https://api.data.gov/signup/)
```

**USDA env var** (nutrient enrichment, `_shared/usda.ts`):

| Var | Default | Notes |
|---|---|---|
| `USDA_API_KEY` | `DEMO_KEY` | Free `api.data.gov` key, ~1,000 req/hr — cached hard (only hit on miss/enrich, never on a cache hit). Absent/empty → enrichment is skipped, OFF-only. |

**LLM env vars** (OpenAI-compatible Chat Completions, provider-agnostic):

| Var | Default | Notes |
|---|---|---|
| `LLM_API_KEY` | _(unset)_ | Absent → no rewrite, raw KB served verbatim (graceful). |
| `LLM_BASE_URL` | `https://api.groq.com/openai/v1` | Any OpenAI-compatible endpoint. |
| `LLM_MODEL` | `llama-3.3-70b-versatile` | |

Enable **anonymous sign-ins** in the project's Auth settings (mirrors
`auth.enable_anonymous_sign_ins = true` in `config.toml`) so the iOS client can
get a JWT before any account exists.

## Invariants worth knowing

- `score_version` is `1.1.0` (`engine.ts`) — bumped from 1.0.0 when
  `additives_risk.json` grew to v1.1 (124 reviewed E-numbers, up from 51). Bump it
  whenever `weights.json` or `additives_risk.json` change; the cache treats older
  versions as stale and rescoring happens on next fetch. Log changes in `MEMORY.md`.
- `products` / `score_results` are a global cache: readable by any signed-in
  (incl. anonymous) session, writable only via the service role. Everything
  user-owned is RLS'd to `auth.uid()`.
- The response of `/product/:barcode` must decode into
  `ios/FoodScanner/Models.swift` — when a product has neither NOVA nor
  Nutri-Score, the `score` object is omitted entirely (band "unknown").
- Additives not in `additives_risk.json` score as low tier and are flagged
  "not yet reviewed" — absence of review is never treated as concern.
- The `ingredient_kb` additive tiers MUST equal the `additives_risk.json` tiers
  (one source of truth). `build_kb_seed.py` derives them; a seed-integrity test
  enforces parity. Never hand-edit `ingredient_kb_seed.json`.
- The AI ingredient endpoint is retrieval-not-generation: no KB entry → no
  explanation, and the LLM can never introduce facts or change the risk tier.
- OCR products (`source=ocr`) have no barcode, no NOVA/Nutri-Score, so they are
  always `data_confidence=limited` with an "unknown" band (no numeric score) —
  honest about label-only data.
- Open Food Facts data is ODbL: keep the attribution in factor sources, and
  share-alike applies to the data.
