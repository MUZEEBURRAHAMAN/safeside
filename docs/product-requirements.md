# Product Requirements

Functional requirements distilled from the user stories in `reference/research/UX_Research_Document.docx`. Tagged to build phases. ACs are testable.

## Epic A — Scan & Understand (Phase 1)
- **A1** Scan a barcode → score + verdict visible without scrolling, ~2s on a mid device.
- **A2** "Why this score" expands to sourced factors with dose context; no factor unexplained.
- **A3** Product not found → snap label → OCR → score, or a clear "can't read" state.
- **A4** Every scan auto-saves to the Pantry; can favorite/remove.

## Epic B — Act on the Verdict (Phase 1–2)
- **B1** Poor score surfaces ≥1 better-scored, restriction-safe alternative. Never a dead-end.
- **B2** Add a product or its better alternative to a meal slot in one tap, with confirmation.

## Epic C — Plan & Shop (Phase 2)
- **C1** Drag products/recipes onto a weekly grid; copy a day; save a template.
- **C2** Generate an aisle-sorted shopping list separating "have" (pantry) from "need".
- **C3** Allergen/restriction conflicts are blocked with a clear reason — never added silently.

## Epic D — Smarter Help (Phase 3)
- **D1** AI fills empty meal slots using only real, scored, restriction-safe products; all numbers DB-computed.
- **D2** AI suggests improvements as an accept/reject diff; user edits are source of truth.

## Epic E — Trust & Onboarding (cross-cutting)
- **E0 (guest-first)** App launches into an anonymous session — no login wall. User can onboard, scan, and build a pantry with **no account**. AC: full core loop works signed-out; nothing blocks on auth.
- **E1** Onboarding ≤8 questions; health/weight questions skippable; no calorie number forced.
- **E2** Sign in with Apple is optional, framed as "save/sync across devices," and links the anonymous account without data loss (no Google sign-in in MVP). AC: signing in preserves existing pantry/history; account deletion available in-app.
- **E3** Price shown before signup/purchase; restore + one-tap cancel discoverable (works on anonymous app-user ID).
- **E4** Score-hiding and calorie-opt-out are real settings honored on every screen.

## Non-functional
- WCAG 2.1 AA; Dynamic Type to XXL; VoiceOver.
- Crash-free sessions ~99%+ at release.
- All API keys server-side; aggressive caching of product/nutrition data.
- Offline-tolerant scan results where cached.
