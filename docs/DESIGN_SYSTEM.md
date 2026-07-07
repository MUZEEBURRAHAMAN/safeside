# Design System — AI Food Scanner + Diet Planner

**Version:** 2.0 · June 2026 · **Bold-green brand direction** (ChemZero-inspired palette)
**Purpose:** A single source of truth so the app looks and feels consistent across every screen. Pair with `UX_Research_Document.docx`.
**Design ethos:** Bold, modern, confident — yet credible and never shaming. A high-energy green identity with a calm, transparent core. The brand can be vivid; the *food scores* stay non-alarmist (a health-safety rule, see §1).

---

## 1. Design Principles

1. **Bold brand, calm scores.** The identity is vivid green and energetic. But food **scores never use alarmist red / "toxic" treatments** — that's an eating-disorder-safety rule (per `CLAUDE.md`), not a style preference. Energy in the brand; neutrality in the verdict.
2. **Legible + credible.** A clear headline answer, with the evidence one tap away. Bold visuals must not bury the facts.
3. **Confident, not shaming.** Strong color and type, but copy stays neutral ("higher-processed", never "bad/toxic").
4. **Action, never a dead-end.** Every result offers a next step.
5. **Native-first, brand-skinned (Apple HIG).** Build on Apple's Human Interface Guidelines and native SwiftUI components — defer to the platform for navigation, gestures, sheets, system controls, haptics, and accessibility. Apply our brand as a *skin* (color, display font, the Score Badge, spacing) on that native foundation. Don't reinvent standard iOS patterns; don't ship a generic un-branded Apple look either. When brand and HIG conflict, HIG wins for behavior/accessibility; brand wins for visual identity. (See §11.1.)
6. **Accessible to everyone.** WCAG 2.1 AA minimum, Dynamic Type, VoiceOver. Bright lime is an accent on dark surfaces only — never small text on white.
7. **Honest surfaces.** Pricing, data confidence, and AI suggestions are always clearly labeled.

---

## 2. Color Tokens

Bold-green palette inspired by the ChemZero/Zentrix references: vivid green + lime accent + near-black green-black, with green-gradient heroes. Semantic tokens first — never hardcode hex; reference the token. **Dark surfaces are first-class** here (the brand looks best on deep green/black with lime accents).

### 2.1 Brand & accents

| Token | Hex | Use |
|---|---|---|
| `color.brand.green` | `#1FC24D` | Primary brand green — active states, highlights, brand mark |
| `color.brand.greenDeep` | `#15803D` | **Primary button fill** (white text passes AA), pressed/active |
| `color.brand.lime` | `#C8F24A` | High-energy accent / CTA — **on dark surfaces only** (lime on white fails contrast) |
| `color.brand.limePressed` | `#B2DD33` | Lime pressed state |
| `color.brand.forest` | `#0E3A24` | Deep green — dark surfaces, gradient base |
| `color.brand.ink` | `#0A140E` | Near-black green-black — headings, dark canvas |

### 2.2 Neutrals (light + dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `color.text.primary` | `#0A140E` | `#F2FBF4` | Body text |
| `color.text.secondary` | `#516057` | `#A9C4B4` | Secondary text, captions |
| `color.text.onGreen` | `#FFFFFF` | `#FFFFFF` | Text on green/forest fills |
| `color.text.disabled` | `#9AA79E` | `#5C6A60` | Disabled |
| `color.bg.canvas` | `#FFFFFF` | `#0B1410` (green-black) | App background |
| `color.bg.surface` | `#F3F8F4` | `#13211A` | Cards, sheets |
| `color.bg.surfaceAlt` | `#E8F6EC` | `#16291F` | Highlighted/info surfaces |
| `color.border.subtle` | `#DCE7E0` | `#26352B` | Dividers, card borders |

### 2.3 Gradients (signature)

| Token | Stops | Use |
|---|---|---|
| `gradient.hero` | `#1B7A43` → `#0B2A1B` (top→bottom) | Onboarding/hero backgrounds (the ChemZero look) |
| `gradient.cta` | `#1FC24D` → `#C8F24A` | Optional vivid accent on dark CTAs / brand moments |

White text on `gradient.hero` passes AA. Reserve `gradient.cta` for hero/marketing moments, not dense UI.

### 2.4 Score scale (brand-tinted, still NON-alarmist)

Ordinal, not traffic-light. "High" uses the brand green so good scores feel on-brand; low uses a muted clay — **never `#FF0000`-style alarm red, never "toxic"** (ED-safe rule).

| Token | Hex | Score band | Label (copy) |
|---|---|---|---|
| `color.score.high` | `#1FC24D` (brand green) | 75–100 | "Lower-processed" |
| `color.score.mid` | `#C9A227` (amber) | 45–74 | "Moderately processed" |
| `color.score.low` | `#B5502E` (clay, not red) | 0–44 | "Higher-processed" |
| `color.score.unknown` | `#7C8A82` | n/a | "Not enough data" |

> Rule: pair every score color with text + icon — color is never the only signal (color-blind safe). This is where we diverge from ChemZero: same bold green energy, but the verdict never screams "toxic".

### 2.5 Feedback

| Token | Hex | Use |
|---|---|---|
| `color.feedback.success` | `#1FC24D` | Confirmations |
| `color.feedback.info` | `#15803D` | Tips, neutral info |
| `color.feedback.warning` | `#C9A227` | Gentle cautions (goal mismatch) |
| `color.feedback.critical` | `#C2381B` | **Reserved for safety only** (allergen block, destructive confirm). Never for food scores. |

---

## 3. Typography

**Display/brand font:** a bold geometric grotesk for headlines and the score number to match the confident brand energy — e.g. **Clash Display**, **Space Grotesk**, or **Satoshi** (Bold/Extrabold). Use sparingly (headlines, hero, score).
**Body/UI font:** **SF Pro** (the iOS system font) — honors Dynamic Type automatically. Use for all body, labels, and dense UI for maximum legibility. (If a future Android client is built, Inter is the equivalent fallback — not relevant to the iOS-only MVP.)

| Token | Size / Line | Weight | Use |
|---|---|---|---|
| `type.display` | 34 / 40 | Bold | Score number, screen hero |
| `type.h1` | 28 / 34 | Bold | Screen titles |
| `type.h2` | 22 / 28 | Semibold | Section headers |
| `type.h3` | 18 / 24 | Semibold | Card titles |
| `type.body` | 16 / 24 | Regular | Default body |
| `type.bodyStrong` | 16 / 24 | Semibold | Emphasis in body |
| `type.caption` | 13 / 18 | Regular | Captions, sources, metadata |
| `type.button` | 16 / 20 | Semibold | Button labels |

Rules: max one `display` per screen. Body never below 16pt (15pt absolute floor). Support Dynamic Type up to XXL without truncation.

---

## 4. Spacing, Radius, Elevation

**4-pt base grid.** Spacing tokens: `space.1`=4, `space.2`=8, `space.3`=12, `space.4`=16, `space.5`=24, `space.6`=32, `space.7`=48.

- Screen padding: `space.4` (16) horizontal.
- Card padding: `space.4` (16). Gap between cards: `space.3` (12).
- **Radius:** `radius.sm`=8 (chips, inputs), `radius.md`=14 (cards, buttons), `radius.lg`=24 (sheets), `radius.full`=999 (pills, FAB).
- **Elevation:** flat by default. `elevation.1` = subtle shadow (y2, blur8, 6% navy) for cards; `elevation.2` (y6, blur16, 10%) for sheets/FAB. Avoid heavy shadows.

---

## 5. Components

Each component: purpose, anatomy, states. States are mandatory — design all of them.

### 5.1 Buttons
- **Primary (light):** filled `brand.greenDeep`, `text.onGreen` (white) label, `radius.md`, min height 48. States: default / pressed (`brand.green`) / disabled (`text.disabled` on `bg.surface`) / loading (spinner replaces label).
- **Primary (on dark/hero):** filled `brand.lime` with `brand.ink` label — the high-energy CTA (lime needs a dark context for contrast).
- **Secondary:** outline `border.subtle`, `text.primary` label.
- **Tertiary/text:** `brand.greenDeep` label, no fill.
- **Destructive:** label/border `feedback.critical` — only for delete/cancel-sub.
- Min touch target **44×44pt**. Label starts with a verb (see copy guide).

### 5.2 Score Badge (signature component)
- Anatomy: large number (`type.display`) + ordinal label + color from score scale + small "i" to expand "why".
- Always shows: number, word label, and an icon — three redundant signals (accessibility).
- Never animates aggressively; a calm fade-in only.

### 5.3 Result Card / "Why this score"
- Collapsed: score badge + product name + one-line summary + "Why this score ›".
- Expanded: factor rows (e.g. additives, processing, sugar), each with a plain-language line, dose context, and a **source link**. A `confidence` chip ("High / Limited data").
- Footer action: **"See a better option"** (primary) — never a dead-end.

### 5.4 Cards (Product, Pantry, Meal slot)
- `bg.surface`, `radius.md`, `elevation.1`, `space.4` padding.
- Pantry card: thumbnail, name, score badge, favorite toggle.
- Meal slot: empty state ("+ Add") vs filled (product/recipe mini-card + score).

### 5.5 Chips / Pills
- Filter chips (diet, restriction): `radius.full`, selected = `brand.green` fill with `brand.ink` label.
- Allergen chip: uses `feedback.critical` outline only in blocking contexts.

### 5.6 Inputs & Forms
- Height 48, `radius.sm`, `border.subtle`; focus = `brand.green` border.
- Inline validation below field; error text in `feedback.critical`, helpful and specific.

### 5.7 Bottom Navigation
- 4 tabs: Home · **Scan (center, elevated FAB-style — `brand.green`/`gradient.cta`)** · Plan · Me.
- Active = `brand.greenDeep` icon+label; inactive = `text.secondary`. Labels always visible.

### 5.8 Sheets, Modals, Toasts
- Bottom sheets (`radius.lg` top) for swaps, add-to-plan, paywall.
- Confirm dialogs name the action ("Delete plan?" / buttons "Delete" · "Keep").
- Toasts: brief, top or above nav, auto-dismiss 3s, never for errors that need action.

### 5.9 Empty, Loading, Error States (design ALL)
- **Empty:** what it is + why empty + one action. (e.g. "Your pantry's empty — scan your first product.")
- **Loading:** skeletons for lists; labeled spinner for AI ("Building a plan from foods you actually buy…").
- **Error:** what happened + how to fix; calm tone; retry affordance. Camera-permission denial → explainer + Settings deep link.

---

## 6. Iconography & Imagery
- Icon set: single, consistent family (e.g. SF Symbols / Lucide), 24pt default, 1.5–2px stroke, `text.primary` or `brand.greenDeep`.
- No alarmist icons (skulls, biohazards, warning triangles) on food scores. Reserve warning iconography for genuine safety (allergens).
- Photography: real food, natural light; can sit on `gradient.hero` green backgrounds for brand moments. Never "before/after" body imagery.

---

## 7. Motion
- Purposeful and quick: 150–250ms, ease-out. Score reveal = gentle fade/scale (no bounce).
- Respect "Reduce Motion": disable non-essential animation.
- Never use motion to create urgency/pressure (no countdown timers on paywall).

---

## 8. Accessibility (WCAG 2.1 AA — non-negotiable)
- Text contrast ≥ 4.5:1 (≥ 3:1 large text); verify all score colors on their backgrounds.
- Color never the sole signal — always pair with text/icon.
- Touch targets ≥ 44×44pt; spacing prevents mis-taps.
- Full VoiceOver labels; score badge announces "Score 38 of 100, higher-processed."
- Dynamic Type to XXL without breaking layout; test at largest size.
- Forms: labels tied to inputs; errors announced.

---

## 9. Voice & Tone (mirrors UX copy guide)
- **Clear, calm, neutral, supportive.** Describe; don't moralize.
- **Use:** score, higher-processed, better option, pantry, plan.
- **Avoid:** bad, toxic, poison, junk, clean, cheat, "you went over."
- Success = quietly affirming; warning = clear + actionable; error = empathetic + fixable.
- **Red lines:** no food-shame, no guilt/streak pressure, no hidden price, never show a calorie number to a user who opted out.

---

## 10. Brand Kit

The portable brand identity — what goes on the app icon, store listing, website, and marketing. Bold green energy, credible core. (References live in `reference/moodboards/branding/`.)

### 10.1 Logo
- **Mark:** a single geometric glyph that fuses a *scan/leaf* idea — e.g. a checkmark/leaf formed inside a rounded square, or a barcode-bar motif. Bold, solid, recognizable at 16px (app icon) and in monochrome.
- **Lockups:** (1) mark only (app icon, avatar), (2) mark + wordmark horizontal, (3) stacked. Wordmark in the display font, Bold/Extrabold.
- **Color use:** `brand.green` or white mark on `brand.ink`/`forest`; `brand.ink` mark on light/lime. App icon: green-black gradient bg + lime/green mark (the ChemZero-style dark icon with a vivid glyph).
- **Clear space:** keep ≥ the height of the glyph's core shape clear on all sides. **Min size:** 24px digital.
- **Don't:** stretch, recolor outside the palette, add shadows/outlines, place the green mark on a clashing background, or rotate.

### 10.2 Color palette (brand)
| Role | Token | Hex |
|---|---|---|
| Primary green | `brand.green` | `#1FC24D` |
| Deep green (buttons) | `brand.greenDeep` | `#15803D` |
| Lime accent (CTA, dark only) | `brand.lime` | `#C8F24A` |
| Forest (dark surface) | `brand.forest` | `#0E3A24` |
| Ink (green-black) | `brand.ink` | `#0A140E` |
| Hero gradient | `gradient.hero` | `#1B7A43 → #0B2A1B` |
| Paper (light bg) | `bg.canvas` | `#FFFFFF` |

Mix guidance: lead with green + ink; lime is the spark (small doses, dark backgrounds). Aim ~60% neutral/ink, ~30% green, ~10% lime.

### 10.3 Typography (brand)
- **Display/headlines:** bold geometric grotesk (Clash Display / Space Grotesk / Satoshi), Extrabold, tight tracking — for the logo wordmark, hero headlines, score number.
- **Body/UI:** Inter / SF Pro.
- Headline style: large, confident, sentence case; high contrast on dark green.

### 10.4 Iconography & graphic language
- Geometric, bold-stroke icons; rounded-square containers echo the logo.
- Motifs: scan brackets, leaf, barcode bars — used sparingly as accents, not decoration.
- Patterns: subtle tiled glyph pattern (like the brand-kit references) for empty states / hero fills, low-opacity on forest.

### 10.5 Photography & mockups
- Real food + product shots, natural light, often on `gradient.hero` green or ink backgrounds for brand moments (store screenshots, web).
- Device mockups: dark UI with green/lime accents shows the brand best.
- Never: before/after body imagery, fear/“toxic” visuals, stocky clichés.

### 10.6 App Store presence
- Icon: green-black gradient + vivid mark.
- Screenshots: dark green hero panels with bold short headlines + a UI screen; lead with the transparent score and the scan→plan loop.
- Tone in store copy mirrors the voice guide — confident, never alarmist.

### 10.7 Do / Don't (brand)
- **Do:** bold green + ink, lime as a spark, generous space, one display headline per view.
- **Don't:** lime text on white (fails contrast), neon on neon, alarmist red/“toxic” on scores, more than one vivid accent fighting for attention.

---

## 11. Theming & Implementation Notes (native iOS)
- Implement tokens in **one place**: an Asset Catalog color set + a Swift `Theme`/`DesignTokens` enum (e.g. `Color.brandGreen`, `Spacing.s4`). SwiftUI views consume tokens, never raw hex.
- Support light/dark via Asset Catalog appearances; test both (this brand leans dark — make dark first-class).
- Use the bold display font via a custom font registered in the app; body uses SF Pro (system).
- Keep one scoring-color mapping function shared by Scan and Plan (consistency = trust).
- Verify contrast whenever using lime — it is an accent on dark surfaces, never small text on white.
- Document any new component here before shipping it (variants, states, a11y notes) to prevent drift.

### 11.1 Apple HIG — what to defer to the platform vs. brand-override
| Defer to Apple (use native, don't reinvent) | Brand overrides (our identity) |
|---|---|
| Navigation (`NavigationStack`, tab bar), back gestures | Color palette + gradients (bold green) |
| Sheets, alerts, context menus, swipe actions | Display/headline font + the score number |
| System controls (toggles, pickers, steppers, search) | The Score Badge + "why this score" card |
| Haptics, Dynamic Type, VoiceOver, Reduce Motion | Spacing rhythm, card radius, elevation |
| SF Symbols for standard icons; standard gestures | Accent usage (lime on dark), empty-state voice |
| Standard control sizing & 44pt targets | Illustration / imagery style |

Rules of thumb: prefer a native component with a brand tint over a custom reimplementation; keep platform behavior (gestures, focus order, accessibility) exactly as iOS users expect; apply brand through color/type/tokens, not by replacing system interactions. Read the current Apple HIG for any pattern before building a custom one. This keeps the app feeling native and trustworthy while still unmistakably ours.

---

*This is a living document. Update the version and changelog when tokens or components change. Consistency across screens is itself a trust signal in a category where users are primed to be skeptical.*
