# UX Copy Deck

**Version:** 1.1 · July 2026 (v1.1 adds the pre-Phase-D surfaces — see §New surfaces; written to the ux-writing patterns: `[what happened]. [why]. [what to do]`, 8–14-word sentences, verbs first, no blame, no dead-ends)
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

## Home (redesign — wordmark + how-it-works carousel + quick actions)
- Wordmark: "SafeSide" · greeting: "Know what's really in your food."
- Carousel 1: "Scan any barcode" / "Point your camera, get a result in seconds."
- Carousel 2: "See a sourced score" / "Every number cited, dose-aware — no black box."
- Carousel 3: "Swap for a better option" / "A better choice in the same category."
- Quick actions: "Scan" · "Search" · "Categories" · "Favorites"
- (Recent-scans empty reuses Pantry §: "Your pantry's empty — scan your first product.")

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

## Errors (what happened + how to fix — never "Something went wrong")
- Network: "You're offline. We'll show saved results; reconnect to scan new items."
- Server hiccup (generic backend/parse failure — not offline, not not-found): "That didn't load right. Give it a moment and try again." [Retry] (Chunk 6 — replaces every banned "Something went wrong")
- Lookup fail: "Couldn't reach the product database. Check your connection and try again." [Retry]
- Load fail (section): "Couldn't load {section}. Tap to retry." [Retry]
- AI fail: "Couldn't generate a plan right now. You can build one manually." 

## Success (quietly affirming, never over the top)
- Plan saved: "Plan saved."
- List ready: "Your list's ready."
- First scan: "Nice — your first scan's in your pantry."

---

## New surfaces (v1.1 — pre-Phase-D chunks; MASTER_PLAN_PRE_D)

### Result upgrades (Chunk 1)
- Meters section headers: "Watch-outs" · "Benefits" (never "Negatives/Positives" — softer, still honest)
- Meter row pattern: "{Nutrient} {value}{unit} — {tier word}" e.g. "Saturated fat 26.7 g — high" · "Fiber 4.5 g — good source"
- Counts pre-read: "{n} ingredients to know about · {n} beneficial"
- Confidence caveat (estimated): "Estimated — {field} isn't on the label." 
- Confidence caveat (OCR): "Scored from a label photo. Some details may be missing."
- Source row pattern: "{Source name} · updated {date}"
- Report issue row: "Report an issue"
- Report sheet title: "What looks wrong?"
- Report reasons: "Score seems off" · "Wrong product info" · "Missing ingredient" · "Something else"
- Report free-text label: "Tell us more (optional)"
- Report submit: "Send report" → Success: "Thanks — we'll review it."
- Report error: "Couldn't send your report. Check your connection and try again." [Retry]
- Additive severity words (map from `riskTier` low/moderate/higher — neutral, mirrors the in-product "…-concern additive" language, never "bad/toxic"): "Lower concern" · "Moderate concern" · "Higher concern"
- Additive category pill labels (factual INS-class names, from the E-number): "Colours" · "Preservatives" · "Antioxidants" · "Thickeners & emulsifiers" · "Acidity regulators" · "Flavour enhancers" · "Sweeteners" · "Other"
- Meter tier-word ladder (backend-owned; the client only interpolates the word) — Watch-outs: "low" · "moderate" · "high"; Benefits: "low" · "some" · "good source"

### Search & manual barcode (Chunk 2)
- Home field placeholder: "Search any product…"
- Search screen title: "Search"
- Barcode toggle: "Enter a barcode"
- Barcode field label: "Barcode number"
- Default state header: "Recent scans"
- Empty recents (new user, no scans): "No recent scans yet. Search a product name, or enter a barcode." [Scan instead]
- Searching: "Searching Open Food Facts…"
- No results: "No matches for '{query}'. Try the barcode, or snap the label." [Scan instead]
- Search error: "Search isn't available right now. Check your connection and try again." [Retry]
- Loader not-found (searched/typed barcode not in Open Food Facts): "We don't have this one yet. Snap the ingredients label and we'll score it." [Scan instead]
- Unscored row caption (we have no current-version score for it): "Not scored yet"
- Scan-banner manual entry: "Enter barcode manually"

### Swaps (Chunk 3 — replaces the stub tip)
- Sheet title: "Better options in {category}"
- Loading: "Finding better options…"
- Delta chip: "+{n} score"
- Why-better line pattern (sourced facts only): "No {additive} · lower {nutrient}" e.g. "No colours E150d · lower saturated fat"
- Card actions: "View" · "Save to pantry"
- Pantry-match chip: "In your pantry"
- Empty (honest): "Few close matches in this category yet. Here's the nearest — or scan another to compare." [Scan another]
- Restriction note: "Filtered for your allergies." (shown when profile filters applied)
- Error: "Couldn't load better options. Check your connection and try again." [Retry]

### Compare (Chunk 5)
- Entry action: "Compare"
- Screen title: "Compare"
- Winner tint label (a11y): "{Product} scores higher on {metric}"
- CTA: "Pick this one" → "Saved to pantry."
- Compact toggle labels: product names (truncate at 18 chars + ellipsis)
- Compact per-row winner chip: "Higher" (neutral; marks the shown side's own strength on that metric — never a "loser" label on the other side)

### Offline & limits (Chunks 4/6)
- Offline scan attempt: "You're offline. Scanning needs a connection — your pantry still works."
- Offline result partial: "Showing saved details. Reconnect for the latest."
- Chat rate-limit (429): "You've asked a lot in a short time. Give it a minute and try again."
- Chat offline: "Chat needs a connection. Your product details are still here."

### Feedback gate (Chunk 7 — after 3rd successful scan, never onboarding)
- Prompt: "How's SafeSide so far?" — options: "Not great" · "Okay" · "Good" · "Great"
- Not great/Okay → "What should we fix?" [free text] → "Thanks — this goes straight to the team."
- Good/Great → "Glad it helps. Mind rating us on the App Store?" [Rate SafeSide] [Not now]

### Legal & attribution (Chunk 7)
- Me rows: "Privacy policy" · "Terms of use" · "Data sources & attribution"
- Attribution intro: "Product data comes from Open Food Facts, available under the Open Database License (ODbL)."
- Attribution ODbL share-alike note: "Under the ODbL we attribute the data and share alike — improvements to the data stay open."
- USDA line: "Nutrition enrichment from USDA FoodData Central (public domain)."

### Legal bodies (Chunk 7) — ⚠️ DRAFT, LEGAL REVIEW REQUIRED before ship
> Drafted in this deck's voice (calm, plain-language, no dark patterns) for `LegalViews.swift`. **Not reviewed legal copy** — a founder/legal pass is a ship gate. The Privacy body discloses analytics honestly per ANALYTICS_METRICS §8 (no third-party ad/tracking SDKs, data minimization, guest-first, `events`/`app_feedback` usage). Kept verbatim-in-sync with `LegalViews.swift`.

**Privacy policy**
- Intro: "Short version: you can use SafeSide as a guest, we collect as little as we can, and we never sell your data."
- "You're a guest by default": "Nothing is required to scan a product and see its score. You can use the app without an account or sharing your name." / "If you answer the optional setup questions, that's to make suggestions fit you — every question is skippable."
- "What we store": "The things that make the app work: your profile answers, the products you scan, your pantry and favorites, and any plans you build." / "This is tied to a random, pseudonymous account id — not your name or email."
- "Analytics we keep": "We log a small set of in-app events — for example, that a scan started or a score was viewed — so we can see where the app helps and where people get stuck." / "These events carry only your pseudonymous id plus simple values like a score band or a product id. They never include the text you type, your photos, or anything read off a label." / "We don't use third-party ad or tracking SDKs, and we don't sell or share your data with advertisers."
- "Feedback you send": "If you send feedback through the app, your message is stored separately from analytics and read only by our team, to help us fix things."
- "Your control": "You stay a guest until you choose otherwise. A control to clear your on-device data is on the way, and you'll be able to ask us to delete your account data." / "Questions about your data? Reach us at privacy@safeside.app."

**Terms of use**
- Intro: "Short version: SafeSide gives you clear, sourced information about food — it's not medical advice."
- "Information, not advice": "Scores and explanations are for general information. They're not medical, nutritional, or health advice, and they're not a diagnosis." / "For decisions about your health or diet, talk to a qualified professional. Always check the actual product label, especially for allergens."
- "About the data": "Product details come from open databases and public sources. They can be incomplete or out of date, and we can't guarantee every detail is correct." / "If something looks wrong, use \"Report an issue\" on the product — it helps us and everyone else."
- "Using the app": "SafeSide is for your personal, non-commercial use. Please don't misuse the service, try to break it, or scrape it."
- "Changes": "We may update the app and these terms as SafeSide grows. If a change is significant, we'll do our best to make it clear. Continuing to use the app means you accept the current terms." / "Questions? Reach us at hello@safeside.app."
- Shared footer (both screens): "Information only — not medical advice. Allergen data may be incomplete; check labels."

---

### Localization notes
- Avoid idioms ("mathing", "grab"); keep strings short for expansion.
- `{score}`, `{price}`, `{trial}`, `{day}`, `{meal}`, `{allergen}`, `{date}` are variables.
- Keep allergen/safety copy literal and unambiguous across languages.
