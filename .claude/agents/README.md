# Specialist Agents (expertise)

> **PROJECT CONSTRAINT (read first):** this project is **iOS-only, native Swift/SwiftUI** for now (Android is deferred — see `MASTER_PLAN.md`). The `ui-designer` and `app-ui-designer` agents describe Android/Material Design as general skills — **ignore their Android/Material guidance**; design for iOS/SwiftUI + Apple HIG only until Android is on the roadmap.


Specialised design & development assistants for building this app. Each `.md` is a Claude Code subagent definition (frontmatter: `name`, `description`, `tools`, `model`). Invoke them when the task matches their description; they carry deep, role-specific instructions so you get expert guidance during development.

## Available agents

| Agent | Use it for |
|---|---|
| **ux-researcher** | Planning/running interviews, usability tests, surveys; synthesizing findings into insights, personas, journey maps. (Start here — validates the open questions in `MEMORY.md`.) |
| **ux-product-designer** | Turning problems into flows, information architecture, wireframes, validated prototypes; feature definition and journey mapping. |
| **ui-designer** | Visual interface design, design systems, component libraries, accessibility, motion, dark mode. |
| **app-ui-designer** | Native mobile (iOS/Android) screen design — navigation, touch interactions, adaptive layouts, onboarding, paywalls, tab bars, gestures. |
| **ios-app-developer** | Building/architecting/debugging the iOS app — SwiftUI/UIKit, networking, persistence, concurrency, testing, performance, App Store submission. |

## Typical flow (maps to the phased build plan)
`ux-researcher` -> `ux-product-designer` -> `ui-designer` / `app-ui-designer` -> `ios-app-developer`.

## How to use
- In Claude Code (once you start building), these are picked up automatically from `.claude/agents/`. Reference an agent by name or let the task description route to it.
- Point them at the project context first: `CLAUDE.md`, `DESIGN.md`, `docs/DESIGN_SYSTEM.md`, the `docs/` specs, and `reference/`. They must follow the project principles (transparent scoring, ED-safe, bold-green brand, honest pricing).
- These agents reference a generic "context-manager"; in this project the equivalent context is the repo itself — have them read `CLAUDE.md` + the relevant `docs/` spec before starting.

## Note on stack
`ios-app-developer` assumes native SwiftUI/UIKit — which is now the **decided stack** (iOS-only native Swift; see `docs/NATIVE_IOS_STACK.md`). This agent applies directly. The other design agents are platform-agnostic.

## Tools
- `../tools/screensdesign_scraper.py` — Playwright scraper for screensdesign.com (UI inspiration). Captures the site's API JSON + DOM cards. Run `pip install playwright && playwright install chromium` first. Use gently and per the site's ToS; save outputs into `reference/moodboards/` for design reference.
