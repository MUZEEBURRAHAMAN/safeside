/**
 * Additive-category (INS class range) tests — pure, offline.
 */

import { assertEquals } from "jsr:@std/assert@1";
import { additiveCategory } from "./category.ts";

Deno.test("colours (E100–199)", () => {
  assertEquals(additiveCategory("E150d"), "Colours");
  assertEquals(additiveCategory("en:e150d"), "Colours");
  assertEquals(additiveCategory("E100"), "Colours");
});

Deno.test("preservatives (E200–299)", () => {
  assertEquals(additiveCategory("E211"), "Preservatives");
  assertEquals(additiveCategory("E250"), "Preservatives");
});

Deno.test("antioxidants (E300–399) — numeric INS class, incl. E322 lecithin", () => {
  // E322 is functionally an emulsifier but sits in the 300 numeric class; we
  // bucket by pure INS range (no per-entry table), so it reads "Antioxidants".
  assertEquals(additiveCategory("E322"), "Antioxidants");
  assertEquals(additiveCategory("E330"), "Antioxidants");
});

Deno.test("thickeners & emulsifiers (E400–499)", () => {
  assertEquals(additiveCategory("E471"), "Thickeners & emulsifiers");
  assertEquals(additiveCategory("E440"), "Thickeners & emulsifiers");
});

Deno.test("acidity regulators & anti-caking (E500–599)", () => {
  assertEquals(additiveCategory("E500"), "Acidity regulators");
});

Deno.test("flavour enhancers (E600–699)", () => {
  assertEquals(additiveCategory("E621"), "Flavour enhancers");
});

Deno.test("sweeteners (E900–999)", () => {
  assertEquals(additiveCategory("E951"), "Sweeteners");
  assertEquals(additiveCategory("E950"), "Sweeteners");
});

Deno.test("other ranges (E700–899, E1000+) → Other", () => {
  assertEquals(additiveCategory("E750"), "Other");
  assertEquals(additiveCategory("E1200"), "Other");
});

Deno.test("case-insensitive and tolerant of en: prefix / trailing letter", () => {
  assertEquals(additiveCategory("e621"), "Flavour enhancers");
  assertEquals(additiveCategory("EN:E150D"), "Colours");
  assertEquals(additiveCategory("  e211 "), "Preservatives");
});

Deno.test("non-additive / unmapped tokens → null", () => {
  assertEquals(additiveCategory("Sugar"), null);
  assertEquals(additiveCategory("en:sugar"), null);
  assertEquals(additiveCategory("Carbonated water"), null);
  assertEquals(additiveCategory("E50"), null); // below the E-number range
  assertEquals(additiveCategory(""), null);
});
