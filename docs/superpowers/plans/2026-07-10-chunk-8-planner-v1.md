# Chunk 8 — Planner v1 (OPTIONAL / founder-gated) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax. Also query `ui-ux-pro-max` (`--stack swiftui`, `--domain ux`) before building each view and run its Pre-Delivery Checklist as a merge gate; route every new user-facing string through `/ux-writing` into `docs/COPY_DECK.md` before use.

> **⚠️ GATE — READ FIRST.** This chunk is **OPTIONAL pre-Phase-D and only starts after Chunks 1–3 have shipped AND the founder green-lights it** (MASTER_PLAN_PRE_D §Chunk 8). If not green-lit, do NOT build: the Plan tab keeps the calm placeholder in `PlanView.swift` into Phase D. Everything below is gated behind a build/runtime flag (Task 1) so a half-built planner can never reach users; the placeholder remains the default until the flag flips.

**Goal:** Turn the Plan tab from a "coming soon" placeholder into a working weekly meal planner: a 7-day × meal grid the user fills from their pantry or search, an AI assist layer that *suggests editable* fills/improvements (LLM selects & explains; **code does every number**), and a have/need shopping list — all ED-safe (no calorie/macro numbers surfaced to users who haven't opted in).

**Architecture:** Backend-heavy, thin client, exactly like `/chat`.
- **New DB migration** `supabase/migrations/20260710000000_planner.sql`: `plans`, `plan_slots`, `shopping_list_items` tables (from `docs/DATA_MODEL.md` §2), owner-only RLS mirroring `pantry_items`. `recipes` stays deferred — v1 slots reference `product_id` only (grounded, DB-computable). New enums `meal_type`, `plan_slot_source`, `aisle_type`.
- **New shared backend module** `supabase/functions/_shared/planner/`: pure, network-free candidate retrieval + hard-filter + macro-recompute logic (the grounding + "code is the calculator" core), unit-tested with Deno like `_shared/scoring` and `_shared/kb`.
- **New edge function** `supabase/functions/plan-assist/` (`index.ts` wiring + `handler.ts` logic + `handler_test.ts`), modeled 1:1 on `chat/`: service-role reads for the product cache, user-scoped read for the caller's profile under RLS, `createLlmClient` from `_shared/llm.ts`, structured-JSON output constrained to candidate IDs, code-side verify/re-check. LLM never emits numbers or free-text foods.
- **New numeric solver step** (Task 5, optional-within-optional): OR-Tools/PuLP "diet problem" fix pass. Deno edge functions are TypeScript-only, so the solver ships either as (a) a `glpk.js`/`javascript-lp-solver` LP call inside `plan-assist` (Deno-native, no new infra), or (b) a separate Python (PuLP/OR-Tools) microservice the edge function calls. Decision flagged for founder in Task 5; default = (a) Deno-native LP so the chunk needs no new deploy target. Either way the solver only satisfies *hard numeric constraints over the candidate set* — it never invents foods.
- **New client files:** `PlanModels.swift` (plan/slot/shopping models + Codable), `PlanService.swift` (`@Observable`, PostgREST CRUD + shopping-list derivation, mirrors `PantryService`), `PlanView.swift` **replaced** (grid + states), plus small planner subviews (slot picker sheet, AI-diff sheet, shopping list) kept in `PlanView.swift` or a `PlannerViews.swift` to match the one-file-per-screen convention.
- **Client edits:** `APIClient.swift` (+`planAssist(...)`), `FoodScannerApp.swift` (inject `PlanService`, feature-flag the tab body), `ProductView.swift` / `ResultComponents.swift` ("Add to plan" entry once swaps land — Chunk 3 dependency).

**Tech Stack:** SwiftUI iOS 17+, `@Observable`, supabase-swift (PostgREST), `URLSession`/`Codable`; Supabase Postgres + RLS; Deno edge functions (TypeScript, `jsr:@std/assert@1`); OpenAI-compatible LLM via `_shared/llm.ts` (Groq/Cerebras) with JSON structured output; LP solver via `glpk.js` (Deno) or PuLP/OR-Tools (Python service). XcodeGen (`xcodegen generate` before every `xcodebuild`).

---

## Dependencies & sequencing note (CRITICAL — chunks may build out of order)

Per MASTER_PLAN_PRE_D §Sequencing (`0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → (8?)`), this chunk assumes:

1. **Chunk 2 (Search + `GET /search`)** — the slot picker's "add from search" path (Task 9) calls the same `/search` edge function. **If Chunk 2 is NOT yet shipped:** build the slot picker with the **pantry-only** source (from `PantryService.entries`) and stub the search field behind the same feature flag; leave a `// TODO(chunk-2): wire /search source` at the search branch. Pantry-first is the spec's primary grounding source anyway (AI_PLANNER_SPEC §2 step 2), so pantry-only is a valid v1.
2. **Chunk 3 (Swaps + `GET /product/:id/swaps`)** — the "Add to plan" entry point from a swap card (Task 12) depends on the swaps sheet existing. **If Chunk 3 is NOT yet shipped:** skip the swap-card entry point; the planner is still reachable from the Plan tab and the manual/AI paths work standalone. Add the entry point when swaps lands (leave a tracked TODO in `ResultComponents.swift` near the `NextActionSheet`).
3. **Chunk 4 (`product_current_scores` view)** — candidate retrieval (Task 3) should read **current** scores, not highest-ever. **If Chunk 4's view does NOT yet exist:** compute current-score inline in `plan-assist` the same way `PantryService.loadTrending` does today (`score_results` ordered by `computed_at desc`, keep first per product) — see `PantryService.swift:96-99`. Add a `// TODO(chunk-4): read product_current_scores view` and switch the query when the view lands (mirror the note MASTER_PLAN §Sequencing requires in both plans).
4. **Chunk 1 (meters/`ResultSkeletonView`)** — not a hard dependency; the planner reuses `ScoreBadge`/grade dots that already exist. No inline fallback needed.

**Standing rules that gate merge** (MASTER_PLAN §Standing rules): principles gate (transparency, **ED-safe**, honest states, never-a-dead-end, **LLM-never-does-math**, AA a11y); teardown AVOID list; `ui-ux-pro-max` Pre-Delivery Checklist; all copy from `docs/COPY_DECK.md`; matrix screenshots before device, device review before merge; MEMORY.md + STATE.md entry on completion. **Key-rotation warning:** this chunk exercises the LLM route — confirm the Cerebras/Groq keys were rotated (STATE.md warning) before running any live `plan-assist` generation.

## Global Constraints
- **Tokens only** — no raw hex/pt literals in views (`Theme.Space`, `Theme.Radius`, `Theme.greenDeep`/`greenSoft`, `DisplayType`). Spacing tokens exist at `Theme.swift:33-35`; display fonts at `DesignKit.swift:33-42`.
- **ED-safe, ship-blocking:** never render a calorie or macro *number* unless the caller's `profiles.show_calories == true` (`DATA_MODEL` `show_calories` defaults false; read via `ProfileService.profile?.showCalories`). Qualitative framing only otherwise ("more protein", "lighter"). The LLM is told never to output numbers (AI_PLANNER_SPEC §3); the client additionally gates any number behind the flag.
- **LLM never does the math:** every macro/score shown is recomputed in code from `products.nutrients` / `score_results`; the model returns candidate IDs + a short rationale only. A returned ID not in the candidate set, or any number in model output, is a hard bug (AI_PLANNER_SPEC §4).
- **Copy** exclusively from `docs/COPY_DECK.md` §Planner / §Swaps & add to plan / §Shopping list / §Errors / §Success — never invented inline. Any genuinely new string goes through `/ux-writing` and into the deck first (Task 13 lists the gaps).
- `xcodegen generate` immediately before every `xcodebuild` (project file is generated — STATE.md gotcha).
- Backend verify: `cd supabase/functions && deno task test` (must stay green; add new tests to the same runner). Deno config at `supabase/functions/deno.json`.
- iOS build/test: `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build` then `xcodebuild test -only-testing:FoodScannerTests`.

---

### Task 1: Feature flag + gate (do first — keeps the placeholder safe)
**Files:** New `ios/FoodScanner/AppConfig.swift` flag (verify current contents first), modify `FoodScannerApp.swift:87` (`RootTabView`), keep `PlanView.swift` placeholder as the fallback branch.
- [ ] Add `static var plannerEnabled: Bool` to `AppConfig` — read from an xcconfig/Info.plist key `PLANNER_ENABLED` (default **false**). This is the founder gate; flipping it to true is the green-light.
- [ ] In `RootTabView` (`FoodScannerApp.swift:79-92`), branch the Plan tab: `if AppConfig.plannerEnabled { PlanView() } else { PlanPlaceholderView() }`. Rename the current `PlanView` struct body into a `PlanPlaceholderView` (verbatim move of `PlanView.swift:8-51`) so the calm "Meal planning is coming" screen is preserved as the off-state, and build the new planner as `PlanView`.
- [ ] Keep the DEBUG harness (`FoodScannerApp.swift:34` `SHOW_SCREEN=plan`) pointing at the real `PlanView()` so the screenshot matrix can capture the built planner even while the runtime flag is off.
- [ ] **Exit:** with the flag off the app is byte-for-byte the current placeholder; with it on, the real planner mounts. No user can reach a half-built planner.

### Task 2: DB migration — planner tables + RLS (backend contract)
**Files:** New `supabase/migrations/20260710000000_planner.sql`. Model from `docs/DATA_MODEL.md:92-133`; mirror RLS style of `20260707000000_initial_schema.sql:195-215` (pantry_items).
- [ ] New enums: `create type meal_type as enum ('breakfast','lunch','dinner','snack');` · `create type plan_slot_source as enum ('manual','ai','swap');` · `create type aisle_type as enum ('produce','dairy','pantry','frozen','bakery','meat','other');`
- [ ] `plans` — `id uuid pk default gen_random_uuid()`, `user_id uuid not null references auth.users(id) on delete cascade`, `week_start date not null`, `title text`, `is_template boolean not null default false`, `created_at timestamptz not null default now()`. Unique `(user_id, week_start)` for the active (non-template) week (partial unique index `where is_template = false`).
- [ ] `plan_slots` — `id`, `plan_id uuid not null references plans(id) on delete cascade`, `day int not null check (day between 0 and 6)`, `meal meal_type not null`, `product_id uuid references products(id) on delete set null`, `recipe_id uuid` (nullable, unused v1 — column present for forward-compat, no FK yet), `source plan_slot_source not null default 'manual'`, `servings numeric not null default 1 check (servings > 0)`. Index `plan_slots (plan_id, day, meal)` (DATA_MODEL §4). No unique on `(plan_id,day,meal)` — a slot can hold multiple items (e.g. two snacks).
- [ ] `shopping_list_items` — `id`, `plan_id uuid not null references plans(id) on delete cascade`, `product_id uuid references products(id) on delete set null`, `label text` (for non-product lines), `aisle aisle_type not null default 'other'`, `qty numeric not null default 1`, `in_pantry boolean not null default false` ("have" vs "need"), `checked boolean not null default false`. Index `(plan_id)`.
- [ ] RLS: `enable row level security` on all three; owner-only select/insert/update/delete keyed on the **plan owner**. `plans` uses `auth.uid() = user_id`. `plan_slots`/`shopping_list_items` have no `user_id` column, so scope via a subquery: `using (exists (select 1 from plans p where p.id = plan_id and p.user_id = auth.uid()))` and the same in `with check`. This matches the "users read/write only their own plans/lists" rule (DATA_MODEL §5).
- [ ] `updated_at` not required (no such column); no trigger needed.
- [ ] **Deploy + test:** apply locally `supabase db reset` (or `supabase migration up`); verify RLS with two anonymous sessions — session A cannot select session B's plan/slots/list rows. Add a psql smoke check (`set role authenticated; set request.jwt.claim.sub = ...`) documented in the migration comment. Push with `supabase db push` only after founder review of the migration.

### Task 3 (TDD): Backend shared planner core — candidates, hard filters, macro recompute
**Test file first:** `supabase/functions/_shared/planner/planner_test.ts` (Deno, `jsr:@std/assert@1`). **Then** `supabase/functions/_shared/planner/planner.ts` (pure, network-free — DB rows arrive as plain args, like `_shared/scoring/engine.ts`).
- [ ] Types: `PlannerCandidate { id, name, mealRoles: MealType[], macros: Macros, score: number|null, band, tags: string[] }`; `Macros { energyKcal, proteinG, carbsG, fatG, satFatG, sugarsG, fiberG, saltG }` (keys from OFF nutriment fields `energy-kcal_100g`, `proteins_100g`, `carbohydrates_100g`, `fat_100g`, `saturated-fat_100g`, `sugars_100g`, `fiber_100g`, `salt_100g` — `products.nutrients` is a passthrough `Record<string,unknown>`, see `_shared/off.ts:76`). `HardFilters { allergens: string[], dietPattern: string|null, dislikes: string[], minScore: number|null, minProteinPerMeal: number|null }`.
- [ ] **Test cases (write before implementation):**
  - `recomputeMacros` reads only DB nutrient fields, rounds to 1 dp, and returns `null` fields when the source key is absent (never invents a number) — **property: output equals DB recompute** (AI_PLANNER_SPEC §5 determinism).
  - `applyHardFilters` drops any candidate whose `allergens_tags` intersects the profile's `allergies` (defense: prefix-stripped compare, reuse `stripPrefix` pattern from `chat/handler.ts:184`).
  - `applyHardFilters` drops diet-incompatible items (e.g. `vegan` + a milk allergen tag / non-vegan tag), dislikes, and (when set) `score < minScore` and `proteinG < minProteinPerMeal` for GLP-1.
  - **Adversarial:** vegan + peanut allergy + `minScore=60` over a mixed fixture → zero forbidden items in the candidate set across 100 shuffles (AI_PLANNER_SPEC §5).
  - `buildCandidateSet` caps to top-N per meal role (cost bound, §4) ordered by score desc, deterministic tie-break by id.
  - `mealRolesFor(product)` maps categories/tags to breakfast/lunch/dinner/snack heuristically; unknown → all roles (never excluded for lack of a role).
- [ ] Implement to green. Keep it exported and pure so `plan-assist/handler.ts` and its tests reuse it (same pattern as `buildCandidates` reused by `chat/handler.ts:35`).

### Task 4 (TDD): Backend `plan-assist` edge function — LLM assemble + code verify
**Test file first:** `supabase/functions/plan-assist/handler_test.ts` (fake `Deps`, mocked `LlmClient`, no network — mirror `chat/handler_test.ts:1-70`). **Then** `handler.ts`, then `index.ts` wiring.
- [ ] **Endpoint contract** (client path `POST /functions/v1/plan-assist`):
  - Request body: `{ mode: "fill" | "improve", weekStart: string (ISO date), mealStructure: { mealsPerDay: int, snacksPerDay: int }, existingSlots: { day:int, meal:MealType, productId:string }[], showCalories: boolean }`. `productId`s validated as UUIDs (reuse `UUID_RE`, `chat/handler.ts:80`).
  - Response body: `{ suggestions: { day:int, meal:MealType, productId:string, rationale:string }[], notes: string, disclaimer: string }`. Every `productId` in `suggestions` **must** be in the code-built candidate set; `rationale` is prose only (no numbers). `disclaimer` = the shared `DISCLAIMER` constant (`chat/handler.ts:60`).
  - Error/degradation: no LLM key → `{ suggestions: [], notes: <canned>, ... }` so the client falls back to manual (never a crash — mirror `CANNED_UNAVAILABLE`, `chat/handler.ts:63`). Banned word in any rationale → drop that suggestion (reuse `hasBannedWord` from `_shared/kb/kb.ts`). 404 when a referenced product isn't in the DB; 401 without `Authorization`; 400 on invalid body.
- [ ] **Deps** (injected, network-free core): `getPantryCandidates()`, `getProductCandidates(filters)`, `getProfile()` (RLS user-scoped, like `chat/index.ts:92`), `getProductsByIds(ids)` (for macro recompute + post-assembly re-check), `llm: LlmClient | null`, `now()`.
- [ ] **Pipeline (AI_PLANNER_SPEC §2), all numbers in code:**
  1. Compute targets in code — qualitative always; numeric (Mifflin-St Jeor) computed **only** when `showCalories` (and never returned to the client as a number in v1; used solely to steer step 4).
  2. Retrieve candidates (Task 3 core) filtered by hard constraints from the profile.
  3. LLM assembles: bounded system prompt (see below) + candidate set (IDs + names + roles + tags, **no macros in the prompt** so the model can't parrot numbers) + existing slots for "improve". `response_format: json_object` (already set in `_shared/llm.ts:80`), `maxTokens` capped.
  4. Verify & fix in code: recompute the assembled plan's macros from DB; re-apply hard filters (defense in depth — drop any slipped-through item, §4); if a hard numeric target is missed, either re-prompt once with the specific gap or hand off to the Task 5 solver.
  5. Return editable suggestions (never auto-applied server-side).
- [ ] **System prompt** (new constant `PLAN_SYSTEM_PROMPT`, built to AI_PLANNER_SPEC §3): calm/non-judgmental; **choose only from the provided candidate IDs, never invent a food**; **never output calories, macros, or any number — only ids + a short rationale**; honor goal framing; banned words (`bad/toxic/poison/junk/clean/cheat/dangerous`); prefer pantry items; respect meal roles and weekly variety. Return `{ "slots": [{ "day", "meal", "product_id", "rationale" }], "notes" }`.
- [ ] **Test cases (write before implementation):**
  - **Adversarial profile (ship-blocking):** vegan + nut allergy + low budget → 100 generations, **zero** forbidden items in `suggestions` (post-assembly re-check catches any LLM slip).
  - **No hallucinated products:** model returns an id not in the candidate set → that suggestion is dropped/regenerated; never surfaced.
  - **No LLM numbers:** any digit-bearing token in a `rationale` → rejected/rewritten; assert `suggestions` never carry a macro (property test).
  - **Fallback:** `llm === null` → `{ suggestions: [] }` + canned note; handler never throws.
  - **Determinism:** same (profile + candidates + mode) input yields the same code-recomputed macros for identical suggestions.
  - **Guardrail parity:** banned word in a rationale → suggestion filtered (reuse `hasBannedWord`).
  - Validation/404/401/400 paths (mirror `chat/handler_test.ts`).
- [ ] **index.ts wiring:** service-role client for product cache, user-scoped client for profile (copy `chat/index.ts:26-115` structure), `createLlmClient` from env, `Deno.serve((req) => handlePlanAssist(req, buildDeps(req)))`.
- [ ] **Deploy + test:** `deno task test` green; `supabase functions deploy plan-assist`; smoke with `curl -X POST .../functions/v1/plan-assist -H "Authorization: Bearer <anon>" -H "apikey: <anon>" -d '{...}'` → assert every returned id exists and no number appears in any rationale.

### Task 5 (TDD, optional-within-optional): OR-Tools/PuLP numeric fix pass
**Decision to flag for founder:** Deno edge functions are TS-only. Ship the solver as **(a) `glpk.js` inside `plan-assist`** (no new infra — default) or **(b) a separate Python PuLP/OR-Tools microservice** the function calls. Recommend (a) for v1; note (b) as the path if constraints get richer.
**Test file first:** `supabase/functions/_shared/planner/solver_test.ts`. **Then** `solver.ts`.
- [ ] Model the classic **diet problem** over the candidate set: minimize deviation from targets (or minimize count of off-target days) subject to hard numeric constraints (protein-per-meal floor for GLP-1, optional score floor, allergen/diet already pre-filtered). Inputs are code-recomputed macros only — the solver never sees or emits a food it wasn't given.
- [ ] **Test cases:** a fixed golden fixture (5–8 candidates, known optimum) → solver returns the expected selection; infeasible constraints → returns "no feasible fill" (client shows the honest empty/partial state, never a fake plan); solver output is a subset of the candidate ids (no fabrication).
- [ ] Wire as step 4b in `plan-assist` only when the LLM assembly misses a hard numeric target; otherwise the LLM result stands (hybrid: LLM for variety, solver for hard numbers — AI_PLANNER_SPEC §2 step 4).
- [ ] **Exit:** golden diet-problem test green; if founder defers the solver, `plan-assist` ships with the "re-prompt once, else return partial" path from Task 4 and this task is marked deferred in MEMORY.md.

### Task 6 (TDD): iOS models — `PlanModels.swift`
**Test file first:** add cases to `ios/FoodScannerTests` (Swift Testing / XCTest — target currently has 0 tests per chunk-0 notes; create `PlanModelsTests.swift`). **Then** `ios/FoodScanner/PlanModels.swift`.
- [ ] Models mirroring the migration with snake_case `CodingKeys` (same convention as `PantryModels.swift:203`): `PlanRow`, `PlanSlotRow` (`meal: MealType`, `source: PlanSlotSource`, `servings: Double`), `ShoppingListItemRow` (`inPantry`, `checked`, `aisle`), enums `MealType`, `PlanSlotSource`, `Aisle` (with display `label`s). A `PlannedItem` view-model joining a slot to its cached `ProductRow`/`ScoreResultRow` (reuse `PantryModels.swift` rows; add `asProduct()` like `PantryEntry.asProduct()` at `:288`).
- [ ] **ED-safe helper (test first):** `func macroDisplay(showCalories: Bool) -> String?` returns `nil` when `showCalories == false` (nothing rendered), a rounded string otherwise. Test: `showCalories=false` → always `nil` regardless of macros present.
- [ ] **Shopping-list derivation helper (test first, pure):** `deriveShoppingList(slots:, pantryProductIDs:) -> [ShoppingListItemRow]` — one line per distinct product across all slots, `in_pantry = pantryProductIDs.contains(id)` ("have" vs "need"), qty = summed servings, aisle from a product→aisle map (default `.other`). Tests: dedup across days; have/need split correct; empty slots → empty list.
- [ ] **Codable round-trip tests** for every row model (encode→decode equality), like the implicit contract on `PantryItemRow`.

### Task 7 (TDD): iOS `PlanService.swift` (`@Observable`)
**Test file first:** extend `PlanModelsTests`/new `PlanServiceTests` for the pure helpers (network CRUD is integration-tested manually; keep derivation/gating logic pure and unit-tested). **Then** `ios/FoodScanner/PlanService.swift` — mirror `PantryService.swift` structure (guards on `session.isBackendReachable`/`supabaseClient`/`userID`, optimistic writes, calm `loadError` copy from COPY_DECK).
- [ ] Observable state: `currentPlan: PlanRow?`, `slots: [PlanSlotRow]`, `plannedItems: [PlannedItem]`, `shoppingList: [ShoppingListItemRow]`, `isLoading`, `loadError`, `isGenerating`.
- [ ] `loadCurrentWeek(weekStart:)` — fetch/create the active `plans` row for the week, its slots, join to cached products/scores (reuse the `products`+`score_results` join pattern from `PantryService.loadRecent`, `:76-104`; **current score = first row per product ordered `computed_at desc`**, and add the `// TODO(chunk-4): product_current_scores` note per the dependency section).
- [ ] `addSlot(day:meal:productID:source:)`, `removeSlot(id:)`, `updateServings(id:_)`, `copyDay(from:to:)` — optimistic local mutation + PostgREST write, revert-on-failure (copy the backup/restore idiom from `PantryService.remove`, `:253-272`).
- [ ] `applySuggestions(_:)` — takes `plan-assist` suggestions, writes accepted ones as `source:.ai` slots (only after the user accepts in the diff UI — never auto-applied).
- [ ] `generateShoppingList()` — call `deriveShoppingList` (Task 6), upsert `shopping_list_items`; `toggleChecked(id:)`, `toggleHaveNeed(id:)`.
- [ ] Copy strings (verbatim from COPY_DECK): pantry/plan load fail → §Errors "Couldn't load {section}. Tap to retry."; save success → §Success "Plan saved." / "Your list's ready."; AI fail → §Errors "Couldn't generate a plan right now. You can build one manually."

### Task 8: `APIClient` — add `planAssist`
**Files:** Modify `ios/FoodScanner/APIClient.swift` (add method after `chat(...)`, `:142-145`; request/response types near `ChatRequestBody`, `:130-133`).
- [ ] `struct PlanAssistRequest: Encodable { mode; weekStart; mealStructure; existingSlots; showCalories }` and `struct PlanSuggestion: Codable { day; meal; productId; rationale }`, `struct PlanAssistReply: Codable { suggestions; notes; disclaimer }`.
- [ ] `func planAssist(mode:weekStart:mealStructure:existingSlots:showCalories:) async throws -> PlanAssistReply` → `request("plan-assist", method: "POST", body: ...)` reusing the existing `request<T>` (`:69`) — same auth headers, same `APIError` mapping (`:34-57`). No new error cases needed.

### Task 9: `PlanView` — weekly grid + empty state (flagship screen)
**Files:** Replace `ios/FoodScanner/PlanView.swift` body (the placeholder moved to `PlanPlaceholderView` in Task 1). Query `ui-ux-pro-max --stack swiftui` for grid/scroll patterns before building.
- [ ] `@Environment(PlanService.self)`, `@Environment(PantryService.self)`, `@Environment(ProfileService.self)`. `NavigationStack` with a real title (not hidden toolbar) — "Plan".
- [ ] **Empty state** (COPY_DECK §Planner): "Your week's empty. Add a favorite from your pantry, or let us start a plan for you." with two equal-weight actions **[Start with AI]** and **[Add manually]** — never a single dead-end (principle #4). Honest, calm, no 70%-empty screen (teardown AVOID #14): show the 7-day scaffold behind the prompt.
- [ ] **Grid:** horizontally-paged or vertically-scrolled 7 days × meal rows (breakfast/lunch/dinner + snacks from `profile.mealsPerDay`). Each filled slot = a compact product cell with thumbnail + name + **grade dot/ring** (reuse existing grade-dot component from `HomeView`/`ScoreBadge.swift`; teardown STEAL #15) and a servings stepper. Tap empty slot → slot picker (Task 10). **No calorie/macro numbers** unless `profile.showCalories` (ED-safe).
- [ ] Loading state: specific copy, not "Loading…" (teardown STEAL #14) — AI generating uses "Building a plan from foods you actually buy…" (COPY_DECK §Planner). Error state: inline retry row (reuse the Me-tab retry pattern from chunk-0 `MeView`).
- [ ] Toolbar overflow: "Save this week as a template" and "Copy {day} to…" (COPY_DECK §Planner) — wire to `PlanService.copyDay` / template save.
- [ ] Bottom sticky action → "Fill the gaps" / "Improve this plan" (COPY_DECK §Planner) and a route to the Shopping list (Task 11).
- [ ] Tokens/a11y: `Theme.Space`/`Radius`/`DisplayType` only; `@ScaledMetric` for any glyph+container pair (chunk-0 rule); Dynamic Type reflow; VoiceOver labels per slot ("{day} {meal}, {product}, scores {band}"; empty → "{day} {meal}, empty, add item").

### Task 10: Add-from-pantry/search slot picker + AI-diff review
**Files:** `PlannerViews.swift` (or within `PlanView.swift`) — `SlotPickerSheet`, `AISuggestionsSheet`.
- [ ] **SlotPickerSheet** (bottom sheet, `Radius.lg` top, detents `[.medium, .large]` — the teardown-observed native pattern): header "Which meal?" is set by the caller; source tabs = **Pantry** (from `PantryService.entries`, pantry-first per spec) and **Search** (Chunk 2 `/search`; **if Chunk 2 not shipped, show pantry only + TODO** per dependency note). Rows = product + grade dot; tap → `PlanService.addSlot(...)` → confirmation toast "Added to {day} {meal}." (COPY_DECK §Swaps & add to plan).
- [ ] **AISuggestionsSheet** — triggered by "Fill the gaps"/"Improve this plan". Calls `APIClient.planAssist`. Header on result: "Suggested — you decide. Keep, swap, or edit any item." (COPY_DECK §Planner). Render each suggestion as an **editable diff row** (keep / swap / remove) with the model's `rationale` (prose only) and the code-computed grade dot; **nothing applies until the user taps accept** (`PlanService.applySuggestions`). AI fail → "Couldn't generate a plan right now. You can build one manually." (COPY_DECK §Errors) with the manual path still present (never-a-dead-end).
- [ ] Optional dismissible nudges (COPY_DECK §Allergens & warnings): "This day leans higher-processed. Want a few swaps?" / GLP-1 "Lighter on protein than your goal — a swap?" — dismissible, computed from DB macros, never shaming, honor ED-safe (qualitative, no numbers).

### Task 11: Shopping list — have/need
**Files:** `PlannerViews.swift` — `ShoppingListView`.
- [ ] Header "Shopping list"; two groups **"Have"** / **"Need"** (COPY_DECK §Shopping list) from `ShoppingListItemRow.inPantry`. Empty state "Build a plan to generate your list." Rows are checkable (`toggleChecked`) with aisle grouping; item can move Have↔Need.
- [ ] At-shelf affordance (STEAL, closes the loop): a "Scan to compare" entry that opens the scanner and, on a better result, "This one fits your plan better." (COPY_DECK §Shopping list). Shelf scans already feed the pantry (user-flows §5) — reuse the existing scan path.
- [ ] Success toast on generate: "Your list's ready." (COPY_DECK §Success). Tokens/a11y as Task 9.

### Task 12: Entry point — "Add to plan" from a swap (Chunk 3 dependency)
**Files:** `ios/FoodScanner/ProductView.swift` (near the next-action buttons, `:130-137`) and/or the swaps sheet from Chunk 3; `ResultComponents.swift` `NextActionSheet` (`:1289`).
- [ ] When Chunk 3's swaps sheet exists, add a secondary **"Add to plan"** action on a swap card / result (COPY_DECK §Swaps & add to plan) → opens a compact "Which meal?" picker → `PlanService.addSlot(source:.swap)` → "Added to {day} {meal}." For a not-in-pantry item: "Add to shopping list to grab next shop." (COPY_DECK §Swaps & add to plan).
- [ ] **If Chunk 3 not shipped:** skip this task; leave `// TODO(chunk-3): Add-to-plan from swap card` beside `NextActionSheet`. The planner is fully usable without it.
- [ ] Gate the entry point behind `AppConfig.plannerEnabled` so it doesn't appear while the planner is off.

### Task 13: Copy audit + gaps to draft via `/ux-writing`
- [ ] Confirm every string above is present in `docs/COPY_DECK.md` §Planner (`:48-55`), §Swaps & add to plan (`:36-42`), §Shopping list (`:62-66`), §Errors (`:84-88`), §Success (`:90-93`), §Allergens (`:57-60`). These are implemented **verbatim**.
- [ ] **Missing strings that must be drafted via `/ux-writing` and added to the deck before use** (do NOT invent inline):
  - Slot-diff action labels beyond "Suggested — you decide." — the explicit **Keep / Swap / Edit / Remove** button words on a suggestion row.
  - Shopping-list row control labels: mark **Have** / **Need** toggle, "Add to list", checkbox a11y.
  - Servings stepper label + a11y ("Servings, {n}").
  - Qualitative targets phrasing surfaced to the user ("more protein", "less processed", "more variety") when `show_calories` is off.
  - Save-as-template success / rename affordance if added.
  - Screen title strings ("Plan", "Shopping list") if not already tokenized.
- [ ] Run the 4-phase edit (purposeful → concise → conversational → clear) for each and append to `docs/COPY_DECK.md` §New surfaces with a Chunk 8 sub-heading.

### Task 14: Verify — backend, iOS, screenshot matrix, gates
- [ ] **Backend:** `cd supabase/functions && deno task test` → all existing suites + new `_shared/planner/*_test.ts` and `plan-assist/handler_test.ts` green. Adversarial-profile test (zero violations / 100 generations) and no-LLM-numbers property test explicitly pass.
- [ ] **iOS:** `cd ios && xcodegen generate && xcodebuild … build` (zero new warnings) + `xcodebuild test -only-testing:FoodScannerTests` → `PlanModelsTests`/`PlanServiceTests` green (Codable round-trips, ED-safe `macroDisplay` gate, shopping-list derivation).
- [ ] **ED-safe device check (ship-blocking):** with a `show_calories = false` profile, walk the whole planner — grid, AI diff, shopping list, nudges — and confirm **no calorie/macro number renders anywhere**; flip the toggle on and confirm numbers appear only then.
- [ ] **Fallback check:** with `LLM_API_KEY` unset (or forced error), "Fill the gaps" returns the manual-fallback state, not a crash or a fake plan (AI_PLANNER_SPEC §5 fallback).
- [ ] **6-shot screenshot matrix** (MASTER_PLAN process line): Plan empty, Plan filled, Slot picker, AI-diff sheet, Shopping list on **SE-proxy (iPhone 17e)** / **iPhone 17 Pro** / **iPhone 17 Pro Max** × **default** + **XXL (AX5)** Dynamic Type via the `SHOW_SCREEN=plan` harness (`FoodScannerApp.swift:34`). No clipping; glyphs scale with their circles; grid reflows; long product names truncate gracefully.
- [ ] **Gates:** principles (transparency, ED-safe, honest states, never-a-dead-end, **LLM-never-does-math**, AA a11y) · teardown **AVOID** list (no alarm-red/shaming, no badge soup, no unsourced numbers, no gamification) · `ui-ux-pro-max` Pre-Delivery Checklist (App UI: icons, interaction, light/dark contrast, layout, a11y) · `/ios-design-review` on the sim shots · device install + founder review.
- [ ] **On completion:** MEMORY.md decision entry (planner v1 shipped/deferred, solver decision (a)/(b), current-score inline vs view) + STATE.md status line update. If the founder did NOT green-light, record "Chunk 8 gated OFF — placeholder retained" and stop after Task 1's flag scaffolding.

---

## Exit criteria (mirrors MASTER_PLAN §Chunk 8 + the standard gate)

**Chunk-specific (MASTER_PLAN Exit):** plan a week from pantry + swaps; the shopping list generates; **ED-safe review passes — no calorie surfacing to opted-out users.**

**Standard gate:** deno tests green (existing + new planner/plan-assist suites, incl. adversarial zero-violation + no-LLM-numbers property tests); iOS tests green; 6-shot screenshot matrix (SE-proxy iPhone 17e / 17 Pro / 17 Pro Max × default / XXL) clean; device install + founder review; principles + teardown-AVOID + `ui-ux-pro-max` Pre-Delivery Checklist gates all pass. Marked clearly **OPTIONAL / founder-gated** — if not green-lit, only Task 1's flag scaffolding lands and the placeholder is retained.
