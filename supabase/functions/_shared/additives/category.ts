/**
 * Additive category from an E-number — pure INS-class range math.
 *
 * The Codex INS / EU E-number system groups additives into functional classes
 * by numeric range. We bucket by range only (no per-entry data table), so this
 * is deterministic and needs no maintenance as new E-numbers appear:
 *
 *   E100–199  Colours
 *   E200–299  Preservatives
 *   E300–399  Antioxidants (numeric class; some are acidity regulators/emulsifiers)
 *   E400–499  Thickeners & emulsifiers
 *   E500–599  Acidity regulators & anti-caking agents
 *   E600–699  Flavour enhancers
 *   E900–999  Sweeteners (numeric class; also glazing agents / gases)
 *   E700–899, E1000–1599  Other
 *
 * Source: Codex Alimentarius INS / EU Regulation (EC) No 1333/2008 numbering.
 * Returns the display label, or null for anything that is not a food E-number
 * (plain food tokens, numbers outside the E100–E1599 range).
 */

// The eight user-facing labels (see docs/COPY_DECK.md §Result upgrades).
const OTHER = "Other";

/** Parse the E-number → display label, or null when it is not an E-number. */
export function additiveCategory(raw: string): string | null {
  if (typeof raw !== "string") return null;
  const cleaned = raw.trim().toLowerCase().replace(/^en:/, "");
  // e + 3–4 digits + optional trailing letter(s), e.g. "e150d". A leading "e"
  // is required so plain food words ("sugar") never resolve to a number.
  const m = cleaned.match(/^e(\d{3,4})[a-z]*$/);
  if (!m) return null;
  const num = Number.parseInt(m[1], 10);

  if (num >= 100 && num <= 199) return "Colours";
  if (num >= 200 && num <= 299) return "Preservatives";
  if (num >= 300 && num <= 399) return "Antioxidants";
  if (num >= 400 && num <= 499) return "Thickeners & emulsifiers";
  if (num >= 500 && num <= 599) return "Acidity regulators";
  if (num >= 600 && num <= 699) return "Flavour enhancers";
  if (num >= 900 && num <= 999) return "Sweeteners";
  if ((num >= 700 && num <= 899) || (num >= 1000 && num <= 1599)) return OTHER;
  return null; // outside the E-number range
}
