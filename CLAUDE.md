# CLAUDE.md — Project Brief (read every session)

> This file gives any AI assistant the context to work on this project consistently. Keep it short and current. Detailed material lives in `docs/` and `reference/`.

## What we're building
An **AI food-ingredient scanner with an integrated diet planner**. Scan a packaged product's barcode → see a transparent, sourced health/processing score → turn it into a weekly meal plan and shopping list built around better choices the user actually buys.

## Who it's for
- **Skeptical Optimizer** — health-conscious, distrusts existing apps' scores. Wants verifiable evidence.
- **Protective Parent** — feeding a family, time-poor, repelled by fear-mongering.
- **Goal-Driven / GLP-1** — wants a realistic plan around foods they tolerate.
(See `reference/research/UX_Research_Document.docx` for full personas.)

## The wedge (why we win)
Every competitor (Yuka, Ivy, Oasis, Cal AI) shares two fixable wounds: users **distrust the scoring** and the apps feel **judgmental / use dark-pattern billing**. We win on **transparency + calm, non-shaming tone + honest pricing + turning verdicts into action.**

## Non-negotiable principles
1. **Transparent scoring** — every score is sourced, dose-aware, and expandable. No black-box verdicts.
2. **ED-safe by design** — neutral language (no "good/bad/toxic"), calories opt-in, no shaming/streaks.
3. **Honest monetization** — price shown before signup, real trial, one-tap cancel.
4. **Never a dead-end** — every verdict offers a next action (better swap → add to plan).
5. **LLM never does the math** — it selects/explains; all nutrition numbers are computed from the DB.
6. **Accessibility** — WCAG 2.1 AA, Dynamic Type, VoiceOver.

## Tech direction (DECIDED: iOS-only, native Swift — see `docs/NATIVE_IOS_STACK.md`)
- **Platform:** native **iOS only** (Swift / SwiftUI). No React Native, no Flutter, no Android for now.
- **Client stack:** VisionKit `DataScannerViewController` (barcode) + Vision `VNRecognizeTextRequest` (OCR) + `URLSession`/`Codable` for OFF & USDA REST + RevenueCat `purchases-ios` (or StoreKit 2) + `supabase-swift` + SwiftUI `@Observable`.
- **Backend (unchanged):** Supabase Postgres + Edge/Node-Python for scoring, the OR-Tools/PuLP optimizer, and the AI route (Vercel AI SDK server-side). iOS is a thin client; all keys + math live on the backend.
- All third-party libs MIT/Apache. OFF data is ODbL (attribute + share-alike on data).
- Superseded: the React Native / Expo recommendation and the smooth-app fork option (Flutter) in `reference/build/Master_Build_Plan.docx`.

## Current status
**Building — MVP + Phase-3 depth are live on a physical iPhone; backend deployed to Supabase.** App name: **SafeSide**. See `STATE.md` for the authoritative current status + how to resume. (This line supersedes the earlier "no code yet.")

## Where things live
- **`STATE.md` — resume brief, READ FIRST: current status, build/run/deploy, secrets, gotchas, next steps.**
- `DESIGN.md` — UI direction summary · `docs/DESIGN_SYSTEM.md` — original tokens/brand · **`docs/DESIGN_SYSTEM_V3.md` — the LIVE design system (light-first; supersedes v2 visuals)**
- `MEMORY.md` — decisions log (newest at top)
- `docs/` — brief, product requirements, design decisions, and specs (scoring, data model, backend, data sources/APIs, ingredient-AI, API, copy deck, metrics, test plan) · `docs/NATIVE_IOS_STACK.md` — the decided native iOS stack · `docs/DATA_SOURCES.md` — open APIs (OFF, USDA, Open*Facts family)
- `reference/research/` — market + UX research · `reference/build/` — build & phase plans
- `reference/competitors/`, `reference/flows/`, `reference/screenshots/`, `reference/moodboards/` — supporting notes & visual references
- `.claude/agents/` — specialist agents (ux-researcher, ux-product-designer, ui-designer, app-ui-designer, ios-app-developer); see its README
- `.claude/tools/` — dev utilities (screensdesign scraper for UI references)

## Specialist agents (use during build)
Five role-specific assistants live in `.claude/agents/`. Route work to them: research → product design → UI/app design → iOS dev. They must read this file + the relevant `docs/` spec before starting, and follow the project principles above.

## Working agreements for AI assistants
- Default to the principles above; flag anything that violates them.
- Be honest and evidence-based; no flattery. Surface risks early.
- When adding a component or decision, record it in `MEMORY.md` / `docs/design-decisions.md`.
