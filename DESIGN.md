# DESIGN.md — Visual Identity & UI Direction

> Summary of the design direction. Full tokens, components, and states live in `docs/DESIGN_SYSTEM.md`.

## Design ethos
**Bold, modern, confident — but credible and never shaming.** A high-energy green identity (ChemZero-inspired) with a calm, transparent core. The brand can be vivid; the *food scores* stay non-alarmist (ED-safe rule). Full palette + brand kit in `docs/DESIGN_SYSTEM.md`.

## Look & feel in one line
Bold green + green-black, lime as the spark. Confident headlines, dark hero gradients — with a clear, sourced score and evidence one tap away.

## Core visual decisions
- **Foundation:** native-first, built on **Apple HIG** + native SwiftUI components (defer to the platform for navigation, gestures, sheets, system controls, accessibility). Our brand is a *skin* on that foundation — see `docs/DESIGN_SYSTEM.md` §1 principle 5 + §11.1 for the defer-vs-override split.
- **Color:** vivid green (`#1FC24D`), deep green buttons (`#15803D`), lime accent on dark (`#C8F24A`), green-black ink (`#0A140E`), green hero gradient (`#1B7A43→#0B2A1B`). Dark surfaces are first-class. Score scale is **brand-tinted but non-alarmist** — brand green / amber / clay, never blaring "toxic" red. Critical red is reserved for safety only (allergen blocks), never for food scores.
- **Type:** bold geometric display font (Clash Display / Space Grotesk / Satoshi) for headlines + score; Inter / SF Pro for body. One display headline per screen; body never below 16pt.
- **Layout:** 4-pt spacing grid, generous whitespace, `radius.md` (14) cards, flat-with-subtle-shadow elevation.
- **Motion:** quick (150–250ms), purposeful, calm; never used to create urgency/pressure.
- **Iconography:** one consistent family (SF Symbols / Lucide). No alarmist icons (skulls, biohazards) on scores.

## Signature components
- **Score Badge** — large number + ordinal word label + color + "why" affordance. Three redundant signals (a11y).
- **"Why this score" card** — sourced factor rows with dose context and a confidence chip. Footer always offers a better option.
- **Bottom nav** — Home · **Scan (center, elevated)** · Plan · Me.

## Voice & tone
Clear, calm, neutral, supportive. Use: *score, higher-processed, better option, pantry, plan.* Avoid: *bad, toxic, poison, junk, clean, cheat.* No food-shame, no guilt, no hidden price.

## Hard rules
- WCAG 2.1 AA contrast; color never the only signal.
- Touch targets ≥ 44×44pt.
- Honor "Reduce Motion".
- Never show a calorie number to a user who opted out.

→ Implement all colors/spacing/type as **tokens** (Asset Catalog color sets + a Swift `Theme`/`DesignTokens` enum, e.g. `Color.brandGreen`, `Spacing.s4`); SwiftUI views reference tokens, never raw hex. Document any new component in `docs/DESIGN_SYSTEM.md` before shipping it.
