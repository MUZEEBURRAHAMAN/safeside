# Claude Code — Kickoff Prompt

Open Claude Code with this folder as the working directory (it auto-reads `CLAUDE.md`), then paste the prompt below as your first message.

---

## Primary kickoff prompt (copy-paste)

```
You're the iOS engineer on this project. Read these first, in order, and treat them as the source of truth — do not write code until you have:
- CLAUDE.md (principles) and MASTER_PLAN.md (phases + "Current state & next action")
- docs/NATIVE_IOS_STACK.md (the decided stack) and docs/BACKEND_SPEC.md
- docs/SCORING_METHODOLOGY.md, docs/DATA_MODEL.md, docs/AI_INGREDIENT_EXPLANATION.md
- docs/DESIGN_SYSTEM.md + DESIGN.md, docs/COPY_DECK.md, docs/TEST_PLAN.md
- The existing scaffold in ios/FoodScanner/ and ios/README.md

HARD CONSTRAINTS (never violate; if something conflicts with these, stop and ask me):
1. iOS-only, native Swift/SwiftUI, iOS 17+. No Android, no cross-platform, no React Native/Flutter.
2. Native-first + Apple HIG, brand as a skin. Build on native SwiftUI components and Apple HIG
   (navigation, gestures, sheets, system controls, haptics, Dynamic Type, VoiceOver, SF Symbols,
   44pt targets). Apply the brand only via color/type/tokens/the Score Badge. On conflict, HIG wins
   for behavior/accessibility, brand wins for visuals. Follow DESIGN_SYSTEM.md §1 #5 and §11.1.
   Do NOT reinvent standard iOS patterns; do NOT ship a generic un-branded look.
3. Guest-first: an anonymous session from launch, no login wall. Sign in with Apple is optional/later.
4. Scoring is deterministic in CODE (docs/SCORING_METHODOLOGY.md). The LLM NEVER invents scores,
   nutrition numbers, or ingredient facts — it only rewrites vetted, cited data
   (docs/AI_INGREDIENT_EXPLANATION.md).
5. ED-safe + non-alarmist: neutral copy (never "toxic/bad"), calories opt-in, score colors
   green/amber/clay — never alarm red. Use design tokens (Theme.swift), never raw hex.
6. All secrets live on the backend; never in the app bundle or committed to the repo.

FIRST MILESTONE — Phase 0 → first vertical slice. Work in small, verifiable steps and show me a
short plan + get my OK before each step:
  1. Turn ios/FoodScanner/ into a real Xcode project (SwiftUI, iOS 17+); add SPM deps: supabase-swift
     and RevenueCat purchases-ios; add NSCameraUsageDescription; get it building and running on the
     simulator AND a physical device. Fix any scaffold compile issues.
  2. Build the backend GET /product/:barcode as a Supabase Edge Function: lookup → cache in Postgres →
     fetch Open Food Facts (with a descriptive User-Agent) → compute the deterministic score → return.
     Create the schema from docs/DATA_MODEL.md with RLS + anonymous auth. Attribute Open Food Facts.
  3. Wire APIClient.swift → ScannerView → ProductView so scanning a real barcode returns a scored
     product end-to-end (score + "why this score" + ingredients).
  4. Write Swift Testing unit tests for the scoring engine, asserting it matches the values in
     docs/Scoring_Calibration.xlsx, plus one XCUITest smoke flow (launch → guest → scan screen).

WORKING RULES:
- Propose a short plan before each step; make small, focused commits; write tests as you go.
- Append decisions to MEMORY.md and docs/design-decisions.md.
- If any doc is ambiguous or conflicts, ASK me — don't guess.
- I have a Supabase project ready; I'll give you the project URL and keys when you need them
  (never put secrets in CLAUDE.md or the repo).

Start now by reading the docs, then give me your plan for step 1 (Xcode project setup).
```

---

## Good follow-up prompts (after the first slice runs)

- `Add the OCR label fallback using the Vision framework, per docs/BACKEND_SPEC.md §2 and the /product/ocr endpoint. Handle "not found → snap the label" gracefully.`
- `Build the ingredient-explanation endpoint per docs/AI_INGREDIENT_EXPLANATION.md — seed the ingredient KB from the scoring additives table, retrieval + caching first, then the bounded LLM rewrite. Write the guardrail tests (no hallucination, no banned words, risk-tier == scoring table) before shipping.`
- `Implement the Pantry (auto-save every scan) and the Home recent-scans list, guest-first, per docs/DATA_MODEL.md.`
- `Wire the RevenueCat paywall: price shown before signup, real trial, one-tap cancel, Restore Purchases. Test in StoreKit sandbox.`
- `Do an accessibility + HIG pass on the current screens: Dynamic Type to XXL, VoiceOver labels, 44pt targets, Reduce Motion. Report what you changed.`

## Notes
- The `ios/FoodScanner/` Swift files are a scaffold that wasn't compiled in Xcode — expect small fix-ups on the first build; that's normal.
- The backend (Supabase project, keys) is yours to provision; Claude Code writes the Edge Functions and schema but can't create the project or hold your secrets.
- Route work to the specialist agents in `.claude/agents/` when relevant (research → product → UI → iOS), but remember the project constraint noted there: iOS-only, ignore their Android/Material guidance.
