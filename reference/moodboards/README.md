# Moodboards

Visual inspiration and brand references, added June 2026 (from the connected moodboard folder). Organized into subfolders. Use when designing UI and deciding the brand identity. Keep choices aligned with `DESIGN.md` — and read the design note below before committing to a palette.

## Contents

### branding/
Five brand-identity kits (Gaylord Group, Pixonr, Zentrix + others). Common thread: **bold neon/lime-green + black**, high-energy "tech startup" aesthetic — geometric logomarks, dark backgrounds, mockups (caps, bottles, ID cards), bright accent palettes (e.g. `#23D200`, `#BBFF00`).

### ui-screens/
General app-UI inspiration (8 screens):
- A **nutrition scanner UI** (mint green): "Nutritional Today" dashboard with calories/protein bars, a camera scan screen (Doritos), and a product detail with **Negatives / Positives** colored bars + a "Not fit with your diet" flag. Directly relevant pattern reference for our scan→result→plan flow.
- A **scan/camera concept** with corner-bracket framing and a neon-green accent — useful for the scan screen framing.
- Other layout/interaction references.

### ivy/
Seven screenshots of **Ivy** (direct competitor) — onboarding/scan/result UI. Pair with the competitor teardown in `reference/competitors/` and `reference/screenshots/`.

### video/
`video reference 01.mp4` — motion/interaction reference.

## ⚠️ Design note — a tension to resolve (important)

The **branding kits you collected (neon/lime-green + black, high-energy) conflict with the brand direction in `DESIGN.md`** (calm, trustworthy, non-alarmist; teal/navy, muted). This matters:

- **Lime/neon green + black reads as "energy / gaming / edgy tech."** For a food-*trust* app aimed at skeptical, anxious users, that can feel hyped or aggressive — and bright lime is the exact palette of the **ChemZero** alarmist app we positioned *against*.
- Our wedge is *calm and credible*. The visual identity should reinforce that, not fight it.

**Options to decide (pick one):**
1. **Keep calm direction (recommended):** a grounded, natural green (sage/forest) + warm neutrals + a navy/ink for trust. Keeps the "health, nature, honest" feel without the energy-drink edge. Use the neon kits only for *logo geometry/energy* inspiration, not the palette.
2. **Go bold neon:** distinctive and modern, but test it hard with the Skeptical-Optimizer and Parent personas — verify it reads as trustworthy, not alarmist, before committing.
3. **Hybrid:** calm base palette + one restrained vivid-green accent for the brand mark only (not for scores — scores stay on the non-alarmist scale).

This is a real fork worth a quick decision; record it in `MEMORY.md` and `docs/design-decisions.md` once chosen. The mockups are great craft references regardless of which way you go.

## Steal vs. avoid (quick)
- **Steal:** the nutrition-scanner UI's clear result layout (Negatives/Positives), the camera corner-bracket framing, the clean card system, the logo-grid/safe-area discipline from the brand kits.
- **Avoid:** alarmist red/neon "danger" treatments on scores; high-saturation backgrounds behind dense info; anything that reads as hype over trust.

## How to use
- Pull the closest reference when designing a screen.
- Prefix your own product mockups `ours-` to distinguish from references.
