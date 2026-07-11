# Categories feature — plan (2026-07-11)

> For agentic workers: execute with superpowers:executing-plans. Native SwiftUI iOS; reads Supabase via PostgREST (no new edge function). Brand locked to DESIGN_SYSTEM_V3 (green, Space Grotesk). Oasis parity for structure only.

## What & why
Oasis has a **Categories** page (list of category cards) → tap → **"Top rated in {category}"** (products ranked best-first). Add the same to SafeSide: browse scored products by food category, ranked by our current score.

Entry point (founder ask: "show that card"): a **"Browse categories" card on Home** → `CategoriesView` → `CategoryDetailView`.

## Data reality (drives the stub list below)
- Products only enter the DB when scanned/seeded. Today: **35 products, 23 with `categories_tags`**, 2–8 per category. So category lists are **thin** until more products are scored.
- OFF taxonomy is messy/overlapping (`en:snacks` vs `en:sweet-snacks` vs `en:biscuits`; `en:sodas`/`en:colas`/`en:carbonated-drinks`). We map a **curated** set of clean categories → one-or-more OFF tags rather than surfacing raw tags.
- Scores come from the `product_current_scores` view (Chunk 4). `products` + that view are globally readable (view is `security_invoker`, `grant select to anon`), so the client can query directly — **same pattern as `PantryService.loadTrending`**.

## Architecture
- **Static curated categories** in the app (`FoodCategory`), each = title + SF Symbol + `offTags: [String]`. No backend, no taxonomy fetch.
- **`CategoryService`** (or extend `PantryService`): `loadProducts(for:)` — query `products` ⋈ `product_current_scores` where `categories_tags && offTags`, order `score` desc; reuse the existing `.from(...).order(...)` read + the `product_current_scores` join already in `PantryService.loadTrending` (PantryService.swift:130–170).
- **Views**: `CategoriesView` (list/grid of category cards, Oasis `categories-01.jpeg`) → `CategoryDetailView` (ranked rows, Oasis `list-01.jpeg`). Rows reuse `ProductThumbnail` (ResultComponents.swift:684) + compact `ScoreBadge` + the "Scored/Not scored yet" chip pattern from the redesigned Search rows. Tap → `ProductLoaderView(barcode:)` (identical scored path).
- **Home entry**: a `CategoriesEntryCard` under the hero/search (near HomeView.swift:100) → `NavigationLink { CategoriesView() }`.

## Tasks

### Task 1 — `FoodCategory` model + curated list (TDD the tag mapping)
- [ ] `FoodCategory: Identifiable` — `id`, `title`, `systemImage`, `offTags: [String]`. Curated list (maps to real DB tags):
  - Snacks — `snacks.fill`? use `bag` — `["en:snacks"]`
  - Chocolate & spreads — `["en:chocolate-spreads","en:sweet-spreads","en:confectionary-based-spreads"]`
  - Sodas & colas — `["en:sodas","en:colas","en:carbonated-drinks"]`
  - Beverages — `["en:beverages","en:beverages-and-beverages-preparations"]`
  - Biscuits & cookies — `["en:biscuits","en:biscuits-and-cakes","en:biscuits-and-crackers"]`
  - Breakfast — `["en:breakfasts"]`
  - Sweet snacks — `["en:sweet-snacks","en:confectioneries"]`
  - (add Dairy/Cereal later — thin now)
- [ ] Test: each category has ≥1 tag; tags are lowercase `en:` slugs; no duplicate ids.

### Task 2 — `CategoryService.loadProducts(for:)` (TDD ranking/sort)
- [ ] Query: `products` where `categories_tags` overlaps `category.offTags` (Supabase `.overlaps("categories_tags", value: tags)` or `.contains`), join current score from `product_current_scores`, keep only rows with a score at the current `SCORE_VERSION`, **order score desc**, cap ~50. Return a `CategoryProductRow` (id, barcode, name, brand, imageURL, score, band).
- [ ] Dedup by product id (a product matching two tags appears once).
- [ ] Pure sort/dedup helper unit-tested (feed rows → assert score-desc + unique). The network read mirrors `loadTrending` (verified on-device, not unit-tested).
- [ ] Honest empty result when a category has no scored products (→ empty state in the view, never a spinner-forever).

### Task 3 — `CategoriesView`
- [ ] Oasis `categories-01` layout: navigation title "Categories" (Space Grotesk), a clean list of category cards — leading SF Symbol in a soft-green rounded tile, title (`Font.display`), trailing chevron, hairline divider, v3 floating card. Tap → `CategoryDetailView(category:)`.
- [ ] Uses the static list (no load). Renders instantly.

### Task 4 — `CategoryDetailView`
- [ ] Title "Top rated · {category.title}" (Space Grotesk). Loads via `CategoryService.loadProducts(for:)` on `.task`.
- [ ] Rows: `ProductThumbnail` + name (2 lines) + brand meta + sourced "Scored" chip (only when we have a current score) + trailing compact `ScoreBadge` ring. Ranked best-first. Row tap → `ProductLoaderView(barcode:)`.
- [ ] States: loading skeleton · ranked list · **honest empty** ("No scored products here yet — scan one to start the list." + a Scan action, never a dead-end) · error (calm + retry, reuse the offline/error copy).

### Task 5 — Home entry card
- [ ] `CategoriesEntryCard` (icon + "Browse categories" + subtitle "See top-rated by type" + chevron), v3 floating card, placed under the search field (HomeView.swift ~100). `NavigationLink { CategoriesView() }`.

### Task 6 — Verify
- [ ] Add DEBUG harness routes: `SHOW_SCREEN=categories` (CategoriesView) + `categorydetail` (CategoryDetailView with a seeded category) for the screenshot matrix.
- [ ] `deno task test` unaffected (no backend). iOS `xcodebuild build` + `test` green (new model/service tests).
- [ ] Screenshot categories + a populated category detail (colas has real data: Coke 28 / Zero 41 / water etc.) on iPhone 17 Pro; compare to Oasis `categories-01` + `list-01`.
- [ ] Device: Home → Browse categories → Sodas & colas → ranked list → tap → product.

## COMMENT OUT FOR NOW (scaffold + `// TODO(categories-later)`, use later)
Build the structure but leave these off, clearly marked:
1. **Sub-category filter chips** (Oasis "All / Bottled Water / Flavored Water") — needs a sub-taxonomy we don't have. Leave a commented `filterChips` placeholder in `CategoryDetailView`.
2. **Paywall "Unlock top rated"** pill/blur gating (Oasis gates the best results) — no paywall until Phase D (RevenueCat). Show all results now; leave a `// TODO(categories-later): gate top N behind paywall`.
3. **Category card image thumbnails** (Oasis shows a product photo per category) — use SF Symbols now; comment out an image-based `CategoryThumbnail` for later.
4. **Category product counts** badge ("12 products") on cards — needs a count query per category; comment the `count` field + query.
5. **Dedicated backend** `GET /categories` + `GET /category/:tag/products` edge functions — client PostgREST is enough now; comment a stub note. Revisit if we need server-side ranking/paging.
6. **Dynamic category discovery** (build the list from DISTINCT `categories_tags`) — messy taxonomy; keep the curated static list. Comment the discovery query.
7. **Categories as its own tab** — keep the Home-card entry for now; leave a `// TODO` where a 5th tab could go in `RootTabView`.
8. **Hide-empty-categories** logic — show all curated categories with an honest empty state for now; comment the "only show categories with ≥N scored products" filter.

## Exit criteria
- Home → Browse categories → a category → ranked best-first list of our scored products → tap opens the product. Empty categories show a calm never-dead-end state, not a spinner. Build + iOS tests green. No new backend. Commented-for-later items are scaffolded + `// TODO(categories-later)` tagged, not deleted.

## Not in scope / dependencies
- Data density: category lists stay thin until more products are scanned/seeded (see the pre-score batch idea, roadmap #11). This feature makes seeding more valuable but doesn't require it to ship.
- Reference: Oasis shots in `reference/oasis/` — `categories-01.jpeg` (categories list), `list-01.jpeg` (top-rated-in-category), `product-*` (row/chip styling).
