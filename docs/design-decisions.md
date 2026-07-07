# Design Decisions

Why we made the choices we did. Append new decisions with date + rationale.

## Scoring is transparent, not a black box
**Decision:** every score expands into sourced, dose-aware factors with a confidence chip.
**Why:** the #1 reason users abandon Yuka/Ivy is distrust of opaque scores. Transparency is the product, not a feature.

## Bold green brand, non-alarmist scores
**Decision (June 2026):** the brand identity is a vivid green / green-black, lime-accent look (ChemZero-inspired) — see `DESIGN_SYSTEM.md` v2.0 Brand Kit. BUT the score scale stays brand-tinted and non-alarmist (brand-green/amber/clay), and copy stays neutral ("higher-processed", never "toxic").
**Why:** the founder wants the energetic green aesthetic for distinctiveness; the ED-safe, non-shaming scoring is held as a health-safety guardrail regardless of brand boldness. The split keeps the marketing punchy without the food-shame that harms users and invites dietitian backlash.
**Risk noted:** bold lime can read like the alarmist apps we position against — validate trust perception with target personas before launch.

## Scanner and planner are one connected loop
**Decision:** the Pantry (auto-filled by scans) is a shared spine; verdicts hand off to swaps and the plan.
**Why:** scanner-only apps dead-end; planner-only apps are generic. Connecting verdict→plan→purchase is the market gap.

## Honest monetization
**Decision:** free = scan + score; Pro = planner/swaps/AI. Price shown pre-signup, real trial, one-tap cancel.
**Why:** dark-pattern billing generates the angriest reviews in the category; honesty is free differentiation and avoids the MyFitnessPal "paywall the scanner" mistake.

## AI selects, the database computes
**Decision:** the LLM never does nutrition math or invents products; it arranges DB items, numbers recomputed in code.
**Why:** studies show LLM calorie estimates are off 20–28%. Grounding prevents hallucination and protects credibility.

## Native iOS (Swift/SwiftUI), iOS-only — DECIDED June 2026
**Decision:** build a pure **native iOS app in Swift/SwiftUI**, iOS-only for now. No React Native, no Flutter, no Android. See `docs/NATIVE_IOS_STACK.md`.
**Why:** the founder chose native for best platform fit and first-party scanning/OCR (VisionKit `DataScannerViewController` + Vision) — a real win for a camera-first scanner. Backend (scoring, optimizer, AI) stays server-side and unchanged; iOS is a thin client.
**Trade-off accepted:** no Android path and nothing to fork (smooth-app was Flutter), so the UI is built from scratch.
**Superseded:** the earlier React Native / Expo recommendation and the smooth-app fork option.

## 4-tab navigation, Scan centered
**Decision:** Home · Scan (center, elevated) · Plan · Me.
**Why:** matches the scan-first mental model from Yuka while making the plan surface a peer. Keeps the core loop one tap apart.
