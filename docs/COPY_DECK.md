# UX Copy Deck

**Version:** 1.0 (draft for build) · June 2026
**Voice:** clear, calm, neutral, supportive. Describe — never judge. See `DESIGN.md` §Voice and the UX Research doc §9. Banned words: bad, toxic, poison, junk, clean, cheat, "you went over".

---

## Onboarding
- Intro 1: "Know what's really in your food." / "Scan any barcode for a clear, sourced score."
- Intro 2: "No fear, no shame." / "Plain facts you can check — you decide what matters."
- Intro 3: "Turn it into a plan." / "Build a week around foods you actually buy."
- Sign in: "Continue with Apple" · "Continue with email"
- Profile start: "A few quick questions so suggestions fit you. Skip anything you like."
- Skip control: "Skip for now"
- Health/weight Q helper: "Optional. We'll never show calorie numbers unless you turn them on."

## Scan
- Empty/scan prompt: "Point your camera at a barcode."
- Permission ask: "Allow camera access to scan products. We only use it while scanning."
- Permission denied: "Camera's off. Turn it on in Settings to scan." [Open Settings]
- Scanning: "Reading the barcode…"
- Result (good): "Lower-processed — {score}/100."
- Result (mid): "Moderately processed — {score}/100."
- Result (low): "Higher-processed — {score}/100. Here's why — and a better option."
- Unknown: "Not enough data to score this one yet."
- Why-this-score link: "Why this score"
- Confidence (limited): "Based on partial data."
- Source line: "Data from Open Food Facts."

## Not found / OCR
- Not found: "We don't have this one yet. Snap the ingredients label and we'll score it."
- OCR capture: "Line up the ingredients + nutrition panel."
- OCR fail: "Couldn't read that. Try again in better light."
- Report data: "Looks wrong? Tell us." → "Thanks — we'll review it."

## Swaps & add to plan
- Swaps header: "Better options"
- Swap reason chips: "In your pantry" · "Higher score" · "Similar, fits your plan"
- Add to plan CTA: "Add to plan"
- Pick slot: "Which meal?"
- Confirmation: "Added to {day} {meal}."
- Not in pantry: "Add to shopping list to grab next shop."

## Pantry
- Empty: "Your pantry's empty. Scan your first product to start."
- Favorite: "Saved to favorites."

## Planner
- Empty plan: "Your week's empty. Add a favorite from your pantry, or let us start a plan for you." [Start with AI] [Add manually]
- AI loading: "Building a plan from foods you actually buy…"
- AI result: "Suggested — you decide. Keep, swap, or edit any item."
- Fill gaps CTA: "Fill the gaps"
- Improve CTA: "Improve this plan"
- Save template: "Save this week as a template"
- Copy day: "Copy {day} to…"

## Allergens & warnings (safety = clear, never shaming)
- Allergen block: "Contains {allergen} — matches your profile. Here are safe options."
- Goal nudge: "This day leans higher-processed. Want a few swaps?" (dismissible, optional)
- GLP-1 protein note: "Lighter on protein than your goal — a swap?"

## Shopping list
- Header: "Shopping list"
- Groups: "Have" / "Need"
- Empty: "Build a plan to generate your list."
- At-shelf: "Scan to compare" → "This one fits your plan better."

## Paywall (honest, no pressure)
- Title: "Unlock planning & better-option swaps."
- Price (explicit): "Pro is {price}/year. {trial} free, then {price}/yr."
- Reassurance: "Cancel anytime in one tap. No tricks."
- CTA: "Start free trial" / Secondary: "Restore purchases"
- Trial reminder (push/email): "Your trial ends in 2 days on {date}. You'll be charged {price}. Cancel anytime."

## Settings & account
- Score display: "Show scores" (toggle) · "Hide scores for a calmer view"
- Calories: "Show calorie & macro numbers" (off by default)
- Manage sub: "Manage subscription"
- Cancel: "Cancel subscription" (one tap to system sheet)
- Delete account: "Delete account" → confirm: "Delete your account and data? This can't be undone." [Delete] [Keep]
- Methodology: "How we score" → links to the plain-language methodology page.
- Disclaimer (footer): "Information only — not medical advice. Allergen data may be incomplete; check labels."

## Errors (what happened + how to fix)
- Network: "You're offline. We'll show saved results; reconnect to scan new items."
- Generic: "Something went wrong. Try again." [Retry]
- AI fail: "Couldn't generate a plan right now. You can build one manually." 

## Success (quietly affirming, never over the top)
- Plan saved: "Plan saved."
- List ready: "Your list's ready."
- First scan: "Nice — your first scan's in your pantry."

---

### Localization notes
- Avoid idioms ("mathing", "grab"); keep strings short for expansion.
- `{score}`, `{price}`, `{trial}`, `{day}`, `{meal}`, `{allergen}`, `{date}` are variables.
- Keep allergen/safety copy literal and unambiguous across languages.
