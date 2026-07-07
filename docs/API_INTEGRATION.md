# API & Integration Spec

**Version:** 1.0 (draft for build) · June 2026
**Rule:** all third-party keys live on the backend (Supabase Edge Functions or a small Node/Bun service). The mobile app talks only to **our** API. Never embed OFF/USDA/AI/RevenueCat secret keys in the client.

---

## 1. Architecture (native iOS client)

> Platform decided: native iOS (Swift/SwiftUI). Client uses `URLSession` + `Codable`; see `NATIVE_IOS_STACK.md`.

```
iOS app (Swift) ──HTTPS (URLSession)──> Our API (backend) ──> Open Food Facts
                                                          ├──> USDA FoodData Central
                                                          ├──> LLM provider (AI planner, server-side)
                                                          └──> Postgres (cache + user data)
RevenueCat purchases-ios (client) <──> RevenueCat (entitlements)  // SDK fine client-side
supabase-swift (client) <──> Supabase (auth + data)
```

---

## 2. Our API endpoints (v1)

| Method | Path | Purpose |
|---|---|---|
| GET | `/product/:barcode` | Lookup → cache → score. Returns product + score_result. |
| POST | `/product/ocr` | Body: label image/text → parse → score (fallback). |
| POST | `/product/:id/report` | User flags wrong/missing data. |
| GET | `/pantry` / POST `/pantry` / DELETE `/pantry/:id` | Pantry CRUD. |
| GET/POST/PATCH | `/plans` … | Plan CRUD + slots. |
| POST | `/plans/:id/ai` | AI fill/improve (see AI_PLANNER_SPEC.md). |
| GET | `/plans/:id/shopping-list` | Derived list. |
| GET | `/swaps/:product_id` | Ranked better alternatives. |

Auth: Supabase JWT on every call; RLS enforces ownership.

---

## 3. Open Food Facts (primary product data)

- **Library:** `@openfoodfacts/openfoodfacts-nodejs` (Apache-2.0) on the backend.
- **Endpoint:** `https://world.openfoodfacts.org/api/v2/product/{barcode}.json` (fields filtered).
- **Required fields:** `product_name, brands, nova_group, nutriscore_grade, nutriments, additives_tags, allergens_tags, ingredients_text, serving_size, image_url`.
- **User-Agent:** set a descriptive UA (`AppName/version - contact`) — OFF requires it; requests without it may be throttled.
- **Rate limits:** be polite; cache to Postgres (TTL ~30 days). Batch/queue background refreshes.
- **Licensing (ODbL):** display "Data from Open Food Facts" attribution on product detail; if we ever redistribute a derived database, it must remain ODbL/share-alike. Our app code stays proprietary; only a derived DB would carry the obligation.

## 4. USDA FoodData Central (clean nutrient backbone)

- **License:** public domain (CC0) — no attribution required.
- **Endpoint:** `https://api.nal.usda.gov/fdc/v1/` with API key (server-side env). ~1,000 req/hr — cache.
- **Use:** fill nutrient gaps OFF lacks; preferred source for macro/micro detail. Map FDC nutrient IDs → our normalized `nutrients` jsonb.

## 5. OCR fallback (missing products)

- **On-device:** Apple Vision `VNRecognizeTextRequest` (native). Capture label → extract ingredients + nutrition panel text → send parsed text to `/product/ocr`.
- Backend parses to a provisional product (`source = ocr`, `data_confidence = limited`), scores it, lets the user confirm/correct. Optionally contribute back to OFF.

## 6. AI provider (planner)

- Called **only** from the backend `/plans/:id/ai` route via the Vercel AI SDK. See `AI_PLANNER_SPEC.md` for prompts/guardrails.
- Keep key server-side; rate-limit per user; log token cost + latency; cache identical requests.

## 7. RevenueCat (subscriptions)

- **SDK:** `purchases-ios` (MIT) in the client — or native StoreKit 2 for zero dependency (public SDK key is fine client-side; secret key stays server-side for webhooks).
- Entitlement: `pro`. Free = scan + score; Pro = planner + swaps + AI.
- Implement: paywall with price shown, **Restore Purchases**, and one-tap manage/cancel deep link. Webhook → backend to sync entitlement to `profiles`.
- Use StoreKit sandbox for all purchase testing.

## 8. Error handling & resilience

| Case | Behavior |
|---|---|
| Product not found (OFF/USDA) | Prompt OCR fallback; never hard error. |
| External API down/timeout | Serve cache if present; else friendly retry state. |
| Partial data | Compute score with `confidence = limited`; show chip. |
| AI timeout/refusal | Fall back to manual planner; show "couldn't generate, try again". |
| Rate limited | Backoff + queue; never block the UI thread. |

## 9. Security & secrets
- All secrets in backend env (Supabase secrets / server env). No secrets in the iOS app bundle or repo.
- Validate/sanitize OCR and report inputs. Per-user rate limits on AI + report endpoints to control cost/abuse.

## 10. Attribution & compliance checklist (ship-blocking)
- [ ] "Data from Open Food Facts" shown on product detail.
- [ ] OFF User-Agent set on all requests.
- [ ] USDA used where it improves accuracy (no attribution needed, but fine to credit).
- [ ] RevenueCat Restore + cancel present; price pre-signup.
- [ ] No third-party secret keys in the client bundle.
