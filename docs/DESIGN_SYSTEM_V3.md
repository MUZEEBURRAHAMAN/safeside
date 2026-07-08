# Design System v3 — "Calm Intelligence" (reference-driven)

**Version:** 3.0 · July 2026 · **Supersedes the visual execution in DESIGN_SYSTEM.md** (tokens/principles there still hold; this raises the bar and resolves light-vs-dark).
**Source of truth for the UI rebuild.** Derived from the founder's curated references: `reference/moodboards/ui-screens` (esp. "Ingrex"), `reference/moodboards/ivy`, `reference/moodboards/branding`, `reference/screenshots` (Oasis etc.).

> Founder directive: UI/UX is priority #1, never compromised. Keep + elevate the bold-green identity. Match/beat Yuka, Cal AI/Oasis, Apple Health.

---

## 1. The resolved direction (light-first, green-accent, dark hero)

The best-in-class references (Ingrex, Ivy, Oasis) are **light-first**: a clean, soft canvas, white rounded cards, generous whitespace, bold headings, and **bold green as the accent** — with **dark used only for immersive moments** (the camera/scan screen, an optional score hero). This reconciles "bold green + dark-first" with what actually reads as premium and trustworthy.

- **Light-first surfaces.** Soft off-white/mint-tinted canvas; pure-white cards float on it.
- **Bold green is the accent, not the background.** Green CTAs, green highlights, green brand marks. Big green fills for primary actions and the "good" score band.
- **Dark is a moment, not the mode.** The scan camera screen is dark by nature; a score hero *may* use a dark/gradient panel. The rest is light.
- **Calm verdict rule stays.** Scores never use alarm red — green / amber / clay only.

---

## 2. Color (light-first)

| Token | Value | Use |
|---|---|---|
| `canvas` | `#F4F8F1` (soft mint-white) | app background — NOT pure white; gives cards something to float on |
| `surface` | `#FFFFFF` | cards, sheets |
| `surfaceAlt` | `#EEF6EA` | subtle highlighted/inset surfaces, chips |
| `ink` | `#0E1A12` | primary headings/text (near-black green) |
| `textSecondary` | `#5A6B60` | secondary text, captions |
| `border` | `#E4EDE5` | hairline card borders/dividers (1px) |
| `brand.green` | `#1FC24D` | primary brand green, highlights |
| `brand.greenDeep` | `#12994A` | primary button fill (white text passes AA) |
| `brand.greenSoft` | `#DDF3E1` | green chip/tile backgrounds (ink text) |
| `brand.ink` | `#0A140E` | dark hero/scan surfaces |
| `brand.lime` | `#C8F24A` | spark accent — **dark surfaces only** |

**Score bands (unchanged, non-alarmist, always number+word+icon):** high `#1FC24D`, mid `#C9A227`, low `#B5502E` (clay), unknown `#7C8A82`.

**Usage ratio:** ~70% neutral (canvas/surface/ink), ~25% green, ~5% lime-on-dark. Green earns attention by being scarce outside CTAs and the "good" band.

---

## 3. Typography

- **Display — Space Grotesk (bundled, OFL):** the score number, screen hero headlines, big section titles. Tight, confident. `DisplayType.score/.hero/.h1/.h2` in `DesignKit`.
- **Body/UI — SF Pro (system):** everything else. Dynamic Type everywhere.

Ramp: score 56/bold · hero 30/bold · h1 26/bold · h2 20/semibold (display) — h3 18/semibold · body 16/regular · bodyStrong 16/semibold · caption 13 (SF Pro). Max one display moment per screen region.

---

## 4. Shape, depth, spacing

- **Radius:** cards/tiles `20` (was 14 — refs use large radii), chips/inputs `12`, **primary buttons full pill (`999`)**, sheets `28`.
- **Depth:** soft, low shadows — `y:6, blur:20, black 6–8%` on white cards over the tinted canvas. Never heavy. Border + soft shadow together = the "floating card" look from the refs.
- **Spacing:** 4-pt grid. Card padding `20`. Section gap `28–32`. Screen padding `20` horizontal. Generous whitespace is part of the premium feel — do not crowd.

---

## 5. Signature components (built from the references)

### 5.1 Primary button — full pill
Filled `greenDeep`, white label, height 56, radius full, subtle press-scale (Motion). Secondary = pill outline. Text/tertiary = green label. (Oasis uses black pills; we use green — brand.)

### 5.2 Tri-metric row  ← the key steal (Ingrex "HEALTH / Risk / Process")
Three equal columns mapping directly to our sub-scores: **Nutrition · Additives · Processing** (plain labels; internally the scoring breakdown). Each shows a short qualitative word (e.g. "High / Low / Minimal") + the band tint, small + calm. This surfaces our transparency asset at a glance, above the fold, before the "why" detail. Never color-only (word + subtle tint).

### 5.3 Score display
- **On result hero:** big Space Grotesk number in a band-tinted ring/disc, band word + icon beside it, calm fade/scale reveal. Optional dark/gradient hero panel.
- **On cards/grid:** a small **grade dot / mini-disc** (band color) in the card corner + the number — like Ingrex's A/D dots and Ivy's "29/100" pill.

### 5.4 Product card (grid) ← recent scans as a 2-col grid
White card, radius 20, product image filling the top (aspect-fit on surfaceAlt), name (2 lines) + brand below, a small score dot/mini-disc + band word, favorite heart top-trailing. Two per row on Home. Tap → result. This replaces the current flat list rows.

### 5.5 Metric tile
Rounded square (radius 20, `greenSoft` or surface), a number/stat in display or bold, a small label + SF Symbol. Used for key nutrients ("Fiber 4.5g"), counts ("20 Ingredients", "4 Additives"), and the daily-insight stat. Directly from the refs.

### 5.6 Scan CTA card (Home anchor)
A prominent full-width card ("Scan a product / Check anything") — green fill or bold bordered, big scan glyph, the hero of Home. Not a plain button in a list.

### 5.7 Daily-insight card (optional, Home top)
A calm one-liner card ("3 scans this week") — a friendly anchor, never a guilt/streak mechanic (ED-safe). Keep neutral; no calorie shaming.

### 5.8 Chips / toggles
Pill chips (radius full); selected = green fill, ink label. Dietary toggles = green when on (Ivy). Filter chips already exist — restyle to this.

### 5.9 Scan screen (the dark moment)
Dark camera, brand-green corner brackets forming the reticle, "SCAN LABEL / Point at a barcode" pill, torch, lime accents allowed here (dark surface). Locks green on capture. (Already close — refine to this.)

### 5.10 Onboarding
Full-bleed bold question (display/hero), a stack of large tappable option cards (radius 20, surface, selected = green ring/fill), a pill primary "Continue" + a quiet "Skip" — exactly the Oasis/Ingrex pattern. Progress bar on top. Every step skippable (ED-safe).

---

## 6. Motion
Calm, quick (150–280ms), ease-out, no bounce (`DesignKit.Motion`). Score reveal = gentle fade/scale. Card taps = subtle press-scale (0.97). Respect Reduce Motion (one static path). Never urgency/countdowns.

---

## 7. Accessibility (part of the bar, not after)
AA contrast (verify green fills + lime-on-dark), color never the only signal (band = color+word+icon always), Dynamic Type to XXL (cards reflow, never clip), full VoiceOver labels, 44pt targets, Reduce Motion. Tokens only — never raw hex.

---

## 8. What changes vs current build (the fix-list)
1. Light-first canvas (mint-white) + white floating cards (soft shadow + hairline border).
2. Space Grotesk on all hero/score/section headlines.
3. Recent scans → 2-col product-card grid with grade dots.
4. Add the tri-metric row (Nutrition/Additives/Processing) to the result screen, above "why".
5. Full-pill primary buttons; larger radii (20) on cards.
6. Home gets a real scan-CTA anchor (+ optional daily-insight card).
7. Metric tiles for nutrients/counts.
8. Onboarding → big-question + option-cards + pill Continue/Skip.
9. Scan screen refined to the dark brand-bracket treatment.
