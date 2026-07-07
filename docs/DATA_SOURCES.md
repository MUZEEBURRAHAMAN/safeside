# Data Sources & APIs

**Version:** 1.0 · June 2026 · iOS-only MVP
**Purpose:** the survey behind the data decisions in `API_INTEGRATION.md` / `BACKEND_SPEC.md` — which food/product APIs exist, their licenses, and why we chose what we chose. All product/nutrition lookups happen on the **backend**; the app never calls these directly.

---

## 1. Chosen for the MVP (open + free)

| Source | What it gives | License | Why chosen |
|---|---|---|---|
| **Open Food Facts** (`world.openfoodfacts.org/api/v2`) | Barcode → product: name, brand, ingredients, `nova_group`, `nutriscore_grade`, `additives_tags`, allergens, images | **ODbL** (open data; attribute + share-alike on derived DB) | The only large, open, barcode-keyed food database. Powers the scan. Requires a descriptive User-Agent. |
| **USDA FoodData Central** (`api.nal.usda.gov/fdc`) | Detailed macro/micronutrients for foods | **Public domain (CC0)** | Cleanest license, no attribution needed. Fills nutrient gaps OFF lacks. Free key, ~1,000 req/hr — cache. |
| **OFF additives taxonomy** + regulatory refs (EFSA, FDA, JECFA/WHO, IARC) | Additive identities + risk basis | ODbL / public regulatory data | Feeds the scoring additives table AND the ingredient knowledge base (`AI_INGREDIENT_EXPLANATION.md`). |

**Barcode & OCR need no API** — they're first-party Apple frameworks (VisionKit `DataScannerViewController`, Vision `VNRecognizeTextRequest`). See `NATIVE_IOS_STACK.md`.

---

## 2. Open\*Facts family — the expansion moat (Phase 6)
Same open project, same API/SDK pattern, all **ODbL** — so your scan-and-explain engine extends to new categories with the same integration:

| Source | Category | Use |
|---|---|---|
| **Open Beauty Facts** | Cosmetics / skincare | Phase 6 beauty expansion |
| **Open Products Facts** | General/household products | Phase 6 household |
| **Open Pet Food Facts** | Pet food | Phase 6 pet |

This is a real strategic asset: the founder vision (food → beauty → household → pet) maps onto one open data family. Validate demand per category first (per `MASTER_PLAN.md` Phase 6), but the data plumbing is already the same.

---

## 3. Commercial alternatives (reference only — NOT open, not used)
Documented so the choice is deliberate. These are paid/closed data; avoid for the MVP (cost, lock-in, licensing), but know they exist if OFF/USDA coverage ever falls short in a market.

| Source | Note |
|---|---|
| **Nutritionix** | Large branded + restaurant DB; paid API, proprietary data. |
| **Edamam** | Nutrition + recipe APIs; freemium, proprietary, per-call limits. |
| **Spoonacular** | Recipes + products; paid, proprietary. |
| **FatSecret Platform** | Branded food DB; paid, OAuth, regional. |
| **FoodRepo** (CH) | Open but regional (Switzerland); niche. |

Rule: prefer open (OFF/USDA). Consider a commercial source only to patch a specific coverage gap in a launch market, isolated behind our backend so it's swappable.

---

## 4. Coverage & quality strategy
- OFF coverage is strongest in EU/UK, decent US, thinner elsewhere — **pick a launch region and pre-warm** a few thousand common local products (see `BACKEND_SPEC.md` §8).
- Chronic gaps: missing products / wrong barcode data. Mitigate with the **OCR fallback** + a one-tap **"report/add product"** flow + a data-confidence chip (per pain-point research).
- Cache everything server-side; keep `raw_off` so scores re-derive on `score_version` change.

## 5. Compliance (ship-blocking)
- **Attribute Open Food Facts** on product detail; comply with **ODbL share-alike** for any database you redistribute (your app code stays proprietary — only a derived DB carries the obligation).
- USDA (CC0) needs no attribution.
- Set the OFF **User-Agent**; respect rate limits; scrape nothing outside the APIs.

## 6. Bottom line
For an open, free, iOS-only food scanner: **Open Food Facts (products) + USDA FoodData Central (nutrients)** is the best stack and it's already specced. The Open\*Facts family future-proofs the category expansion. Commercial APIs are a fallback, not a need.
