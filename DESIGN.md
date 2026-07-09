# DESIGN.md — SafeSide Design Charter (v2, July 2026)

> **The authoritative design direction.** Tokens/components live in `docs/DESIGN_SYSTEM_V3.md` (light-first "Calm Intelligence"). Evidence base: `reference/competitors/design-teardown.md` (82-image competitive scan). Per-screen specs: `docs/SCREEN_SPECS.md`. This file supersedes the v1 dark-hero direction previously described here.

---

## 1. Design position (why we look the way we do)

Every competitor fails on one of two axes: **trust** (Yuka/Ivy's black-box scores, ChemZero's fear theater) or **tone** (shaming verdicts, dark-pattern billing). SafeSide's visual identity is engineered to win both:

**Calm Intelligence** — a light, airy, premium surface (mint-white canvas, floating white cards) carrying *dense, sourced evidence* (meters, citations, confidence states). Calm is not shallow; dense is not alarming. That pairing is the design wedge — no competitor does both (Oasis = calm but shallow; Ivy = dense but shaming).

### The five design laws (non-negotiable, from CLAUDE.md, enforced in review)
1. **Every verdict is evidence** — number + word + icon, sourced, dose-aware, expandable. Never color-only, never unsourced.
2. **Calm alarm** — risk is signaled by thin border tints, neutral tier words ("Elevated", "Trace", "Not detected"), and clay (never alarm red) — red is reserved for user-allergen safety only.
3. **Never a dead-end** — every result screen ends in a next action (better option → plan → scan another).
4. **Honest states** — unknown is gray (never green), estimated data says so ("Estimated — fiber % not on label"), loading copy is specific ("Checking additive sources…"), empty states are kind.
5. **ED-safe always** — no streaks, praise-shaming, mortality framing, or calorie surfacing to opted-out users.

---

## 2. Visual identity (summary — tokens in DESIGN_SYSTEM_V3)

- **Light-first.** Canvas `#F4F8F1` (soft mint), white floating cards (radius 20, hairline border + soft shadow). Dark is a *moment*: the scan camera and optional score hero only.
- **Bold green, scarce.** `brand.green #1FC24D` highlights, `greenDeep #12994A` CTA fills, lime `#C8F24A` on dark surfaces only. ~70% neutral / 25% green / 5% lime.
- **Score bands:** high `#1FC24D` · mid `#C9A227` · low `#B5502E` (clay) · unknown `#7C8A82`. Always number + word + icon.
- **Type:** Space Grotesk (display: score, heroes, section titles) + SF Pro (everything else). One display moment per region. Body ≥ 16pt.
- **Shape:** cards 20 · chips/inputs 12 · primary buttons full pill (h 56) · sheets 28.
- **Motion:** 150–280 ms ease-out, no bounce, no urgency. Score reveal = gentle fade/scale. Reduce Motion always has a static path.
- **Iconography:** SF Symbols, one weight family. Never skulls/biohazard/warning-triangle on food scores (triangle allowed only for data-confidence caveats, amber).

---

## 3. Responsive layout system (every iPhone, mandatory)

SwiftUI, iOS 17+. Design once, verify at four widths. **No fixed pixel layouts; no hard-coded screen assumptions.**

### 3.1 Device classes (logical points, portrait)
| Class | Width | Devices (examples) | What changes |
|---|---|---|---|
| **Compact** | 320–375 | SE 2/3, 12/13 mini | 2-col grids stay 2-col with tighter gutters; hero type steps down one ramp; tri-metric row keeps 3-up but compresses labels |
| **Standard** | 390–393 | 12–15, 16, 17 | Reference size. Base spec targets this |
| **Plus** | 402–430 | Plus/Pro models | Wider gutters, content max-width holds |
| **Max** | 430–440 | Pro Max | Same layout, more whitespace; NEVER stretch cards full-bleed-wider — cap content at 400pt readable measure where text-heavy |

### 3.2 Rules
- **Grid:** 20pt screen margins (16pt on Compact). Product grid = `LazyVGrid(columns: adaptive(min 160))` — yields 2-up everywhere, gracefully 3-up on Max landscape/iPad-compat.
- **Readable measure:** long-form text (why-this-score, chat, methodology) capped ~600pt equivalent; use `.frame(maxWidth: 560)` centered on wide layouts.
- **Safe areas:** all screens respect `safeAreaInset`; bottom CTAs sit in a safe-area-inset container, never hard-pinned offsets. Home indicator clearance automatic.
- **Dynamic Type: full range to accessibility XXL.** Cards reflow vertically, never clip or truncate below `.large`. Tri-metric row wraps to vertical stack at accessibility sizes (`ViewThatFits`). Test gate: every screen at XXL before merge.
- **Landscape:** not a target for MVP (portrait-locked is acceptable for scanner apps) — but nothing may *crash* in landscape; keep the lock explicit in project config.
- **Hit targets ≥ 44×44pt** including chips and hearts (pad tap area beyond visual bounds where needed).
- **No magic numbers:** spacing from the 4-pt token scale; screen-relative sizing via `GeometryReader` only at container level, never per-component.

### 3.3 Verification workflow (already wired — use it)
DEBUG harness `SIMCTL_CHILD_SHOW_SCREEN=<screen>` → `xcrun simctl io booted screenshot`. **Matrix per screen: iPhone SE (3rd gen) + iPhone 17 Pro + iPhone 17 Pro Max, each at default and XXL Dynamic Type.** Six screenshots per screen before device install.

---

## 4. Component canon (what exists; build nothing off-canon)

From DESIGN_SYSTEM_V3 §5, extended by the teardown:

| Component | Notes / teardown source |
|---|---|
| Score ring (hero) | Number + band word + icon; gentle reveal |
| Grade dot / mini-disc | Cards, list rows; consider mini-ring (progress) variant |
| Tri-metric row | Nutrition · Additives · Processing; word + tint, 3-up → vertical at a11y sizes |
| **Negatives/Positives meters** *(new)* | Two calm sections, labeled bar meters with values — from `ui-screens 6`; neutral headers ("Watch-outs" / "Benefits" per COPY_DECK) |
| Ingredient card | Thin band-tint **border** (never fill) + 1-line why + expandable (Oasis pattern) |
| **Confidence caveat callout** *(new)* | Amber, "Estimated — X missing from label" (Food Scanner pattern); OCR + thin-data products |
| **Trust footer** *(new)* | Permanent 2 rows on Result: "How this score works" + "Report an issue" (Oasis pattern) |
| Tri-state check card | pass / flag / unknown + reason line (allergens; FS 49) |
| Per-nutrient row | icon + label/value + status word + dot (FS 50) |
| Fact-chip row | small icon+label chips (trust chips — have) |
| Product card (grid) | 2-col, image top, name/brand, grade dot, heart |
| Metric tile | rounded square, stat + label + symbol |
| Scan CTA card | Home anchor, green fill |
| Pill button / chips | primary pill h56; chips radius-full, selected = green fill |
| Option card (onboarding) | large tappable, selected = green ring |
| Empty/loading/error trio | calm copy, specific loading text, always a retry action |
| Sheet | radius 28, drag handle, detents half→full (ingredient/chat) |

**Rule:** new component → spec it in DESIGN_SYSTEM_V3 + this canon first, then build.

## 5. Screen UX standards (summary — full specs in docs/SCREEN_SPECS.md)

Every screen ships with: all four states (content / empty / loading / error) · VoiceOver labels + logical focus order · Dynamic Type XXL verified · dark-scan-moment exceptions documented · a next action (law 3).

Screen inventory (flow order): Onboarding (8Q skippable) → Home → Scan (camera + gallery + OCR fallback) → Result (score, tri-metric, why, ingredients, allergens, chat, swaps, trust footer) → Ingredient detail sheet → Chat sheet → Pantry/Favorites → Search → Compare → Plan (placeholder → planner) → Me (profile, settings, legal/ODbL) → system moments (permissions, paywall Phase D).

## 6. Voice & copy (COPY_DECK governs)
Clear, calm, neutral, specific. Use: *score, higher-processed, better option, watch-outs, benefits, estimated, unknown.* Never: *bad, toxic, poison, junk, clean, cheat, danger, ages you.* Numbers always rounded + unit-labeled; the backend does the math, the UI never re-computes.

## 7. Hard accessibility gates (WCAG 2.1 AA)
- Contrast AA on every text/fill pairing (verify green fills, lime-on-dark).
- Color never sole signal (band = color + word + icon, everywhere).
- 44pt targets; Reduce Motion path; VoiceOver full coverage; Dynamic Type XXL reflow.
- Focus order: verdict → evidence → actions on Result.

## 8. Review checklist (run before any screen merges)
1. Four states present? 2. SE + Pro Max + XXL screenshots clean? 3. Tokens only (no raw hex/pt)? 4. Next action present? 5. Any AVOID-list pattern from the teardown (`design-teardown.md` §Master AVOID)? 6. Copy in deck vocabulary? 7. VoiceOver pass? 8. New components spec'd first?
