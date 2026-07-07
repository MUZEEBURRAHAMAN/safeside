# Competitor Screenshots

61 competitor screenshots, named `competitor-01.jpeg` … `competitor-61.jpeg`. Source: user-provided (WhatsApp export), added June 2026. Use as visual reference when designing UI and for the competitive UX analysis.

The set covers **three App Store apps: Oasis, ChemZero, and Food Scanner.** A sample across the 61 was reviewed (not every file individually catalogued); filenames are sequential, not yet labeled by app — relabel/group as you go (suggested prefixes: `oasis-`, `chemzero-`, `foodscanner-`).

## The three apps (observed clusters)

### 1. Oasis ("What's Healthy") — calm, transparent (closest to our direction)
- **Onboarding:** calm, light UI. Hero with an AR-style fridge shot tagging a water bottle ("Nitrate – 4 health risks", "PFAS – 2x guidelines", "Tap water source"). Headline: "What is marketed as healthy often isn't."
- **Interest picker:** "What products are you interested in?" — Water, Skincare, Food, Personal Care, Supplements, Household, Snacks (multi-select, Skip available).
- **Product detail sheet:** ingredient cards outlined green/red with plain-language descriptions (e.g. Ethyl Alcohol, Aqua), a "Product Details" section ("Form Type: spray", "Ingredient Transparency: Partial disclosure"), and footer actions **"How scoring works"** + **"Report an issue."**

### 2. ChemZero — alarmist seed-oil / "longevity" tone (what NOT to do)
- Onboarding on a green gradient: "Uncover what brands don't tell you", "Detected Risks – High", with red **"Toxic levels of Seed Oils"**, "High levels of PFAS", "Toxic levels of Microplastics", "Moderate levels of Additives", "100% brand-independent data."
- Social proof: testimonials framed around aging/longevity ("It shows which foods are aging you").

### 3. Food Scanner — nutrient panel
- "Nutrient levels" screen: Fat / Saturated Fat / Sugar / Salt / Protein with High/Low/Unknown traffic-light dots (red/green/grey). (Captured with a Google Play install ad overlay.)

## UX takeaways (tie directly to our design decisions)

- **Oasis confirms our calm-transparency direction:** "How scoring works" + "Report an issue" + "Ingredient Transparency" are exactly the trust surfaces we planned (see `docs/SCORING_METHODOLOGY.md`, `docs/design-decisions.md`). Steal the *clarity*; we go further by showing sourced, dose-aware reasoning and a next action (Oasis dead-ends at the verdict).
- **ChemZero is the anti-pattern to avoid:** "Toxic", "harmful ingredients… accelerate aging", red everywhere. This is the fear-mongering our brand explicitly rejects (`DESIGN.md` voice, ED-safe stance). Keep as a "do not do this" reference — and our positioning wedge against it.
- **Food Scanner's traffic-light nutrient dots** are legible but binary; our score scale is deliberately ordinal and non-alarmist (clay, not red) — see `docs/DESIGN_SYSTEM.md`.
- **Oasis onboarding interest-picker** (multi-select + Skip) is a good, low-friction model — consistent with our ≤8-question, skippable onboarding.

## How to use
- When designing a screen, pull the closest competitor screen here for reference.
- Add your own product screens later and prefix them `ours-` to distinguish.
