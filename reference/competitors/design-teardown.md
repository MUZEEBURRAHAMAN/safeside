# Competitive Design Teardown — full visual scan (July 2026)

> Synthesized from a screen-by-screen analysis of **all 82 reference images**: `reference/screenshots/competitor-01…61.jpeg` (Oasis, ChemZero, Food Scanner, Yuka-style scanner), `reference/moodboards/ivy/` (7), `reference/moodboards/ui-screens/` (9, incl. the "Ingrex" composite), `reference/moodboards/branding/` (5 kits). Complements `competitive-analysis.md` (market lens). **This doc feeds `DESIGN.md` and the screen-by-screen specs.**

## Apps covered

| App | Identity | Verdict style | Net lesson |
|---|---|---|---|
| **Oasis** (shots 01–25) | Calm light UI, black pills, chip badges | 0–100 ring + word ("Good"/"Bad") | Best trust surfaces in market; dead-ends at verdict |
| **ChemZero** (26–40) | Saturated green gradient, lime CTA | Binary "Toxic"/"Ages you faster" | The anti-pattern library. Our positioning wedge |
| **Food Scanner** (41–54) | White + orange, Nutri/Eco/Nova badges | Letter grades + traffic-light dots | Great methodology explainers; ad-polluted, badge soup |
| **Ivy** (moodboards) | Cream + teal, red score pills | Blunt red 0–100, sad-face icon | Good info density; shaming verdicts, no sourcing |
| **Ingrex composite** (`screnshot 4.webp`) | Light mint + one bold green | Letter dots on cards | **Closest visual analog to SafeSide — our Home template** |

---

## Per-app profiles

### Oasis — the trust benchmark (steal the surfaces, beat the dead-end)
- **Ingredient cards: thin colored *border*, not fill** (red = concern, green = beneficial) + one-line plain-language description + "Read more". The best "calm alarm" pattern observed. (shots 11, 19, 20)
- **Permanent result-screen footer: "How scoring works" + "Report an issue"** as two neutral utility rows on *every* product page. Single strongest trust component in the whole set. (shot 13)
- **Named, dated inline source citations** ("Oasis – Erewhon … Pesticides Test 2026") under a collapsible "Sources" section. (shot 12)
- **"Ingredient Transparency: Partial disclosure"** as its own labeled field — flags data confidence separately from the verdict. (shot 20)
- **Harmful-count vs beneficial-count paired rows** (6 red-dot / 2 green-dot) before the ingredient list — balanced, non-binary pre-read. **"Owned by [Brand] →"** accountability row. (shot 21)
- **Score = ring + number + word** (73/100 "Good"). Word "Bad" too blunt for us — use descriptive tiers.
- **Onboarding:** emoji-row multi-select interest picker with always-visible Skip (shot 10); permission priming with concrete payoff data + "Not now" (shots 04, 07); honest soft-paywall (blur+padlock on premium *alternatives*; core verdict stays free) (shot 12).
- **Faults:** "Rate us 5 Stars" review gate (shot 05); follower/following vanity metrics on Profile (shot 18); cross-app "Farmr" promo inside a Coming-soon map card (shot 22); Google button styled above Apple (HIG miss, shot 08); cherry-picked all-high scores in onboarding (shot 03).

### ChemZero — the anti-pattern library (avoid everything, cite it in reviews)
- Unsourced dread stats as fact: "credit card of plastic every week", "cut lifespan by 10 years", "500 more calories" — zero citations. (26, 27, 33)
- Fabricated precision: "95% reduction", "82% microplastics blocked", 92%-vs-18% bar chart with no axis/sample/source + fake "verified" badge. (28, 34)
- "Toxic"/"PFAS Confirmed" badges stamped on *stock photos* pre-scan; mortality framing ("Ages you faster") on real named brands. (29, 30, 32)
- Green checkmark semantically inverted to mean "confirmed toxic". (36)
- Paywall: trial toggle games, "POPULAR" badge on the worse-value weekly plan, ₹999/week post-trial price in small text under a big "Try for Free", no cancel-anytime. (37, 38)
- Forced App Store rating prompt mid-onboarding, before any value. (35)
- **One salvageable layout:** severity-word + category-pill row (30) — reusable with neutral tier words ("Elevated / Trace / Not detected") + real citation.

### Food Scanner — methodology explainers worth copying, polish failures to dodge
- **STEAL: "How this score works" sub-page template** — score card + amber "this was estimated because X was missing" caveat callout + plain-language methodology + *named institutions* (Agribalyse/ANEME/INRAE) + external "Learn more" link. Reused consistently across score types via one shared component. (44, 45)
- STEAL: per-nutrient row — icon + label/value + status word + colored dot (50); tri-state allergen/diet cards pass/flag/unknown *with reason line* (49); tappable score rows with chevrons → explainer (42, 47); "Learn more about [X]" link-with-icon as a repeatable trust affordance (54); emoji sentiment gate that routes unhappy users to feedback not the App Store (43) — but trigger after a milestone, never on cold open.
- AVOID: **badge soup** — 4 uncoordinated scoring systems stacked, green background under a *negative* verdict (47); **raw unrounded floats** ("21.3333333333333 g") and mislabeled fields in Nutrition facts — worst polish failure in the set (52, 53); banner ads inline with health content (42, 48, 50); "Unknown" state colored green = false reassurance (45); off-brand boilerplate auth screen (46); radio-style controls on multi-select lists (Ivy 56–57 same fault).

### Ivy — density good, tone bad
- STEAL: per-factor risk card (label + severity pill + meter bar + one-sentence "why") (04); expandable additive rows with explanation (06); pill-toggle allergen list (03); traffic-light score badges on list rows (07); benefit-first permission priming inside the real scan viewport (58); specific loading copy ("Preparing the AI food science engine") (60).
- AVOID: bare red "29/100" pill, frowning-heart + red "20/100" (shaming); danger-colored dots that conflate *present* with *dangerous* (no dose context); mood/anxiety tracking scope creep; no visible "how the score works" anywhere.

### Ingrex composite + UI inspiration — our visual family
- **Ingrex (`screnshot 4.webp`) = the Home template:** light mint canvas, one bold green accent, insight banner, big green "Scan" CTA, recent-scans grid with corner grade dots, center-emphasized tab bar. Already codified in DESIGN_SYSTEM_V3 — confirmed correct.
- **`screenshot 6.jpg` = the Result pattern to absorb: explicit "Negatives / Positives" two-section bar-meter layout** with labeled numeric values per row. Best transparent-scoring layout in the whole set. Soften copy to neutral ("Watch-outs / Benefits" style, per COPY_DECK).
- `screenshot 5.webp`: corner-bracket viewfinder + single helper line; mini progress-ring on recent-scan thumbnails.
- `screnshot 1.webp`: circular hero image + one-sentence verdict + pill chips (result header comp).
- `screnshot 2.webp`: two-chip macro summary (icon+number+label); floating circular FAB on cards → "Add to Plan".
- `app screenshot 01.webp` (Yuka-style): per-ingredient OK/Caution tags + nutrient fact-chip strip.
- AVOID: `screenshot 8.jpg` streak/praise gamification (ED-safe violation); dark+orange gamified dashboard (`screnshot 3.webp`) — tone reference for what we are not.

### Branding kits — technique yes, palette no
- Usable: grid-constructed geometric monogram method; safe-area/clear-space spec diagrams; weight-ladder type specimen format (template for documenting Space Grotesk); rounded organic container holding a letterform, shown across color/ground versions.
- Not usable: every neon-on-black palette (#C6FF1A, #39FF14, #BBFF00) — energy-drink/gaming coding, and literally ChemZero's family. Goli kit's dark-teal→emerald ramp = candidate future dark-mode accent range only.

---

## Master STEAL list → mapped to SafeSide screens

| # | Pattern | Source | Lands on |
|---|---|---|---|
| 1 | Thin colored **border** ingredient cards + 1-line why + Read more | Oasis 11/19/20 | Result (have — verify borders not fills) |
| 2 | Permanent **"How scoring works" + "Report an issue"** footer rows | Oasis 13 | Result — **build; report endpoint is roadmap item A** |
| 3 | Named + dated source citations, collapsible Sources | Oasis 12, FS 45 | Result "why" section (have sources — add named-DB + date) |
| 4 | **"Estimated because X missing" confidence caveat** callout | FS 44 | Result + OCR results (honest-uncertainty surface) |
| 5 | **Negatives/Positives dual bar-meter sections** | ui-screens 6 | Result — absorb into tri-metric detail |
| 6 | Harmful/beneficial paired count rows pre-read | Oasis 21 | Result above ingredient list |
| 7 | Tri-state cards pass/flag/unknown + reason | FS 49 | Allergen alerts (have — align style) |
| 8 | Per-nutrient row: icon+value+status word+dot | FS 50 | Result nutrition detail |
| 9 | Severity-word + category-pill rows (neutral words) | ChemZero 30 layout | Result additive summary |
| 10 | Emoji-row multi-select picker + always-visible Skip | Oasis 10 | Onboarding (have — polish) |
| 11 | Permission priming w/ concrete payoff + "Not now" | Oasis 04/07, Ivy 58 | Camera permission, notifications later |
| 12 | Corner-bracket viewfinder + one helper line + gallery strip | ui-screens 5/7 | Scan (have — refine) |
| 13 | "Identifying" pill over live camera, not blocking spinner | Oasis 17 | Scan lookup state |
| 14 | Specific loading copy, not "Loading…" | Ivy 60 | All loading states |
| 15 | Mini grade ring/dot on product thumbnails | Ingrex, ui-screens 5 | Home grid, pantry rows (have dots — consider ring) |
| 16 | "Owned by [Brand] →" accountability row | Oasis 21 | Result (nice-to-have, OFF has brand owner) |
| 17 | "Learn more about [X]" link-with-icon affordance | FS 54 | Score/methodology links |
| 18 | Sentiment-gated feedback (emoji triage, post-milestone) | FS 43 | Later — before App Store launch |
| 19 | Soft paywall: blur+lock *premium extras*, verdict stays free | Oasis 12 | Phase D paywall |
| 20 | Grouped-card Settings layout | Oasis 24 | Me tab (have — verify grouping) |
| 21 | Calm empty states ("No history yet" + one line) | Oasis 09 | Home/pantry/search empties |
| 22 | Search default state = useful recent list, not blank | Oasis 16 | Search (roadmap item A) |
| 23 | Fact-chip row (icon + 1–2 word label) | Ivy 01, screnshot 1 | Result trust chips (have) |
| 24 | System share sheet as-is; branded image generated *before* invoking | Oasis 25 | Result share (future) |

## Master AVOID list (design review checklist)

1. Alarm-red fills / sad faces / "Bad-Toxic-Confirmed" verdict words — border-tint + neutral tier words only.
2. Unsourced statistics anywhere, ever — every number needs a tappable source (our core principle; ChemZero is the cautionary tale).
3. Mortality/aging/lifespan framing — hard ED-safe violation.
4. Badge soup — one primary verdict; sub-scores demoted and drillable, never four peer badges.
5. Color semantics violations: green under negative verdicts, "Unknown" in green (use neutral gray), checkmarks meaning "bad".
6. Raw unrounded floats / API dumps in user-facing facts — round + label everything (backend does math).
7. Paywall games: pre-selected expensive tier, "POPULAR" on worse value, buried post-trial price, off-default trial toggles. Price loud, cancel-anytime explicit.
8. Rating prompts before value delivered; guilt-framed review copy.
9. Streaks, praise copy, gamified identity, follower counts.
10. Ads or cross-promos inside trust-critical surfaces.
11. Radio-style indicators on multi-select lists; "Skip" present without an equal-weight "Continue".
12. Off-brand boilerplate screens (auth/legal must use the same tokens).
13. Cherry-picked all-good examples in onboarding — show the honest range.
14. 70%-empty key screens — density with calm, not blankness.

## Opportunity map — where SafeSide wins on design

1. **Trust footer everywhere** (Oasis has it; nobody pairs it with dose-aware sourcing) → our "why this score" + How-scoring-works + Report issue trifecta on every result.
2. **Confidence/estimation surfaced as a first-class UI state** (only FS hints at it) → OCR results, thin-data products, "Ingredient Transparency" field.
3. **Verdict → action** — every competitor dead-ends at the score. Our swaps engine + plan CTA is the loop none of them close.
4. **Calm + dense** — Oasis is calm but shallow per-screen; Ivy is dense but shaming. Negatives/Positives meters + per-nutrient rows + bordered ingredient cards = dense AND calm.
5. **Honest monetization as UI** — price-before-signup, real trial, one-tap cancel, verdicts never paywalled. ChemZero/Ivy's dark patterns are our marketing contrast.

## Interaction/motion cues observed
- Draggable bottom sheet with detents (half → full) for ingredient detail — iOS-native pattern (Oasis).
- Loading pill overlay on live camera (non-blocking) — scan feels fast.
- Accordion chevrons for Sources/What's-inside; pick push-vs-accordion consistently (FS mixes them).
- Sticky bottom pill CTA for one-handed reach (keep mechanic, fix copy).
- Toggle → live CTA-label + price swap on paywalls (mechanic fine; price must stay loud).
- No skeleton loaders anywhere in the set → skeletons on Result = free polish differentiator.
