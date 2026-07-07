# Data Model Spec

**Version:** 1.0 (draft for build) · June 2026
**Backend:** Postgres (Supabase). All times UTC. IDs are UUID unless noted.
**Principle:** the **Pantry is the bridge** between scanner and planner — model it from day one. Cache external product data aggressively; never call OFF/USDA on every view.

---

## 1. Entity overview

```
User ──< PantryItem >── Product
User ──< Plan ──< PlanSlot >── (Product | Recipe)
User ── Profile (1:1)
Plan ── ShoppingList (derived)
Product ── ScoreResult (1:1, versioned)
```

---

## 2. Tables

### users (managed by Supabase Auth)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| email | text | |
| created_at | timestamptz | |
| apple_sub | text null | Sign in with Apple |

### profiles (1:1 with user)
| Field | Type | Notes |
|---|---|---|
| user_id | uuid PK/FK | |
| goal | enum | healthier \| less_processed \| lose \| gain \| condition \| budget |
| diet_pattern | enum | omnivore \| flexitarian \| vegetarian \| vegan \| pescatarian \| keto \| mediterranean \| none |
| allergies | text[] | normalized allergen tags |
| dislikes | text[] | ingredient tags |
| meals_per_day | int | + snacks count |
| household_size | int | |
| cook_time | enum | quick \| medium \| enjoy |
| budget | enum | low \| medium \| none |
| health_flags | text[] | diabetes, hypertension, pregnancy, glp1 … (optional) |
| show_calories | bool default false | ED-safe: numbers opt-in |
| score_display | enum default 'shown' | shown \| hidden |
| computed_targets | jsonb null | TDEE/macros from Mifflin-St Jeor (never forced) |

### products (cache of external + our score)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| barcode | text unique | nullable for OCR-only items |
| name | text | |
| brand | text null | |
| source | enum | off \| usda \| ocr \| user |
| nova_group | int null | 1–4 |
| nutriscore_grade | text null | a–e |
| nutrients | jsonb | normalized per-100g + per-serving |
| serving_size | text null | |
| additives_tags | text[] | e-numbers |
| allergens_tags | text[] | |
| ingredients_text | text null | |
| images | jsonb null | urls |
| data_confidence | enum | high \| limited |
| raw_off | jsonb null | original payload for re-derivation |
| fetched_at | timestamptz | cache freshness |
| updated_at | timestamptz | |

### score_results (1:1 current, keep history)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| product_id | uuid FK | |
| score | int | 0–100 |
| band | enum | high \| mid \| low \| unknown |
| breakdown | jsonb | {processing, nutrition, additives} each with sub-score, weight, sources |
| confidence | enum | high \| limited |
| score_version | text | matches SCORING_METHODOLOGY version |
| computed_at | timestamptz | |

### pantry_items (the bridge)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK | |
| product_id | uuid FK | |
| status | enum | scanned \| favorited \| owned |
| first_scanned_at | timestamptz | |
| last_seen_at | timestamptz | |
| unique (user_id, product_id) | | |

### plans
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK | |
| week_start | date | |
| created_at | timestamptz | |
| is_template | bool default false | saved templates |
| title | text null | |

### plan_slots
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| plan_id | uuid FK | |
| day | int | 0–6 |
| meal | enum | breakfast \| lunch \| dinner \| snack |
| product_id | uuid FK null | one of product/recipe |
| recipe_id | uuid FK null | |
| source | enum | manual \| ai \| swap |
| servings | numeric default 1 | |

### recipes (v1 minimal; expand later)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| name | text | |
| ingredients | jsonb | each maps to product_id where possible |
| steps | text[] null | |
| computed_nutrition | jsonb | from DB, not LLM |

### shopping_list_items (derived, materialized per plan)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| plan_id | uuid FK | |
| product_id | uuid FK null | |
| label | text | for non-product ingredients |
| aisle | enum | produce \| dairy \| pantry \| frozen … |
| qty | numeric | |
| in_pantry | bool | "have" vs "need" |
| checked | bool default false | |

### events (analytics; see ANALYTICS_METRICS.md)
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK null | |
| name | text | event key |
| props | jsonb | |
| ts | timestamptz | |

---

## 3. Caching & freshness
- On scan: look up `products` by barcode → if present and `fetched_at` < TTL (e.g. 30 days), serve cached; else fetch OFF/USDA, upsert, recompute score if `score_version` changed.
- Store `raw_off` so scores can be re-derived when methodology updates without re-fetching.
- Background job: re-score products when `score_version` increments.

## 4. Indexing
- `products.barcode` unique btree; `pantry_items (user_id, product_id)`; `plan_slots (plan_id, day, meal)`; `score_results (product_id)`; `events (user_id, ts)`.

## 5. Privacy & RLS
- Supabase Row-Level Security: users read/write only their own profiles, pantry, plans, lists, events.
- `products`/`score_results` are shared/global (cache), read-only to clients; writes via backend only.
- Support account deletion (App Store requirement): cascade delete user-owned rows; keep anonymized aggregate events only.

## 6. Out of scope for v1
- Household sharing (multi-user plans), recipe import, grocery-delivery order objects — design later (Phase 3+).
