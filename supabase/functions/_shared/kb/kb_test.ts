/**
 * Ingredient KB guardrail suite (docs/AI_INGREDIENT_EXPLANATION.md §7) +
 * KB-seed integrity. Offline: the LLM is mocked, no network, no DB.
 *
 * Covers:
 *   (a) no-hallucination      — missing KB field stays "limited", never filled
 *   (b) banned-language       — fear words never reach the output
 *   (c) risk-consistency      — output tier == scoring/KB tier, always
 *   (d) unknown-ingredient    — the limited state, never a fabrication
 *   (e) missing-LLM-key       — degrades to raw KB, still no fabrication
 *   (f) seed integrity        — every additives_risk.json entry has a KB entry
 *                               with the SAME tier
 */

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import type { LlmClient, LlmMessage } from "../llm.ts";
import {
  applyRewrite,
  BANNED_WORDS,
  buildKbIndex,
  explainIngredient,
  hasBannedWord,
  KB_VERSION,
  type KbEntry,
  rawKbToIngredient,
  toIngredientId,
  unknownIngredient,
} from "./kb.ts";
import seed from "./ingredient_kb_seed.json" with { type: "json" };
import additivesRisk from "../scoring/additives_risk.json" with { type: "json" };

// ---------------------------------------------------------------------------
// Fixtures + fakes
// ---------------------------------------------------------------------------

const SEED_ENTRIES = seed.entries as unknown as KbEntry[];

function kbEntry(overrides: Partial<KbEntry> = {}): KbEntry {
  return {
    id: "en:e621",
    names: ["Monosodium glutamate", "MSG", "E621"],
    what: "A flavour enhancer.",
    why_used: "Adds a savoury taste.",
    safety: "EFSA set a group intake limit that some groups can exceed.",
    risk_tier: "moderate",
    who_should_avoid: ["people advised to limit sodium"],
    misconceptions: ["'MSG sensitivity' is not confirmed in blind studies"],
    found_in: ["savoury snacks", "soups"],
    sources: [{ name: "EFSA re-evaluation of glutamates, 2017", url: "https://efsa" }],
    confidence: "high",
    last_reviewed: "2026-07",
    kb_version: KB_VERSION,
    ...overrides,
  };
}

/** A mock LLM returning a fixed JSON string. */
function fixedLlm(jsonOut: string): LlmClient {
  return { complete: (_m: LlmMessage[]) => Promise.resolve(jsonOut) };
}

/** A mock LLM that echoes the provided facts (a faithful identity rewrite). */
const echoLlm: LlmClient = {
  complete(messages: LlmMessage[]) {
    const user = messages.find((m) => m.role === "user")?.content ?? "";
    const idx = user.indexOf("{");
    const facts = idx >= 0 ? JSON.parse(user.slice(idx)) : {};
    return Promise.resolve(JSON.stringify({
      what: facts.what ?? "",
      whyUsed: facts.whyUsed ?? "",
      safety: facts.safety ?? "",
    }));
  },
};

// ---------------------------------------------------------------------------
// (a) no-hallucination
// ---------------------------------------------------------------------------

Deno.test("no-hallucination: a missing KB field is never filled by the LLM", async () => {
  const entry = kbEntry({ why_used: null, safety: null });
  // The LLM tries to invent whyUsed + safety (and a bogus study).
  const rogue = fixedLlm(JSON.stringify({
    what: "A flavour enhancer used in cooking.",
    whyUsed: "Invented reason not in the KB.",
    safety: "A 2099 study proved it is completely risk-free.",
  }));

  const out = await explainIngredient(entry, rogue);
  assertEquals(out.whyUsed, null, "empty KB field must stay limited");
  assertEquals(out.safety, null, "empty KB field must stay limited");
  assertEquals(out.what, "A flavour enhancer used in cooking."); // present → rewrite allowed
});

Deno.test("no-hallucination: arrays + sources come verbatim from the KB, not the LLM", async () => {
  const entry = kbEntry();
  // Even if the LLM emitted extra list items, the handler only reads prose.
  const out = await explainIngredient(entry, echoLlm);
  assertEquals(out.whoShouldAvoid, entry.who_should_avoid);
  assertEquals(out.misconceptions, entry.misconceptions);
  assertEquals(out.foundIn, entry.found_in);
  assertEquals(out.sources, entry.sources);
});

// ---------------------------------------------------------------------------
// (b) banned-language
// ---------------------------------------------------------------------------

Deno.test("banned-language: hasBannedWord matches whole words only", () => {
  assert(hasBannedWord("this is toxic"));
  assert(hasBannedWord("Dangerous levels"));
  assertFalse(hasBannedWord("a cleanser for surfaces cleans"), "no whole banned word");
  assertFalse(hasBannedWord("badminton is a sport"));
});

Deno.test("banned-language: a rewrite with a fear word is discarded for raw KB", async () => {
  const entry = kbEntry();
  const rogue = fixedLlm(JSON.stringify({
    what: "A toxic additive.",
    whyUsed: "Adds a savoury taste.",
    safety: "It is dangerous.",
  }));
  const out = await explainIngredient(entry, rogue);
  // Falls back to raw KB — none of the banned words survive.
  assertEquals(out.what, entry.what);
  assertEquals(out.safety, entry.safety);
  for (const field of [out.what, out.whyUsed, out.safety]) {
    if (field) assertFalse(hasBannedWord(field));
  }
});

Deno.test("banned-language: no seed entry (raw KB path) contains a fear word", () => {
  for (const entry of SEED_ENTRIES) {
    const out = rawKbToIngredient(entry);
    const fields = [
      out.what,
      out.whyUsed,
      out.safety,
      ...out.whoShouldAvoid,
      ...out.misconceptions,
      ...out.foundIn,
    ];
    for (const f of fields) {
      if (f) {
        assertFalse(
          hasBannedWord(f),
          `banned word in ${entry.id}: "${f}"`,
        );
      }
    }
  }
});

Deno.test("banned-language: identity-rewriting the whole seed stays clean", async () => {
  for (const entry of SEED_ENTRIES) {
    const out = await explainIngredient(entry, echoLlm);
    for (const f of [out.what, out.whyUsed, out.safety]) {
      if (f) assertFalse(hasBannedWord(f), `banned word after rewrite in ${entry.id}`);
    }
  }
});

// ---------------------------------------------------------------------------
// (c) risk-consistency
// ---------------------------------------------------------------------------

Deno.test("risk-consistency: an LLM cannot change the risk tier", async () => {
  const entry = kbEntry({ risk_tier: "moderate" });
  // The prose contract has no tier field, but assert the output ignores any.
  const rogue = fixedLlm(JSON.stringify({
    what: "x",
    whyUsed: "y",
    safety: "z",
    riskTier: "low", // ignored
  }));
  const out = await explainIngredient(entry, rogue);
  assertEquals(out.riskTier, "moderate");
});

Deno.test("risk-consistency: every additive's output tier equals the scoring tier", () => {
  const risk = additivesRisk as unknown as Record<string, { tier?: string }>;
  const { byId } = buildKbIndex(SEED_ENTRIES);
  for (const [id, value] of Object.entries(risk)) {
    if (id === "_meta") continue;
    const entry = byId.get(id.toLowerCase());
    assert(entry, `additive ${id} missing from KB seed`);
    const out = rawKbToIngredient(entry!);
    assertEquals(out.riskTier, value.tier, `tier drift for ${id}`);
  }
});

// ---------------------------------------------------------------------------
// (d) unknown-ingredient
// ---------------------------------------------------------------------------

Deno.test("unknown-ingredient: limited state, never a fabricated explanation", () => {
  const out = unknownIngredient("Some Novel Fiber");
  assertEquals(out.name, "Some Novel Fiber");
  assertEquals(out.confidence, "limited");
  assertEquals(out.riskTier, null);
  assertEquals(out.whyUsed, null);
  assertEquals(out.safety, null);
  assertEquals(out.sources, []);
  assert(out.what?.includes("don't have vetted info"));
});

// ---------------------------------------------------------------------------
// (e) missing-LLM-key
// ---------------------------------------------------------------------------

Deno.test("missing-LLM-key: degrades to raw KB fields verbatim", async () => {
  const entry = kbEntry();
  const out = await explainIngredient(entry, null);
  assertEquals(out, rawKbToIngredient(entry));
  assertEquals(out.what, entry.what);
  assertEquals(out.safety, entry.safety);
  assertEquals(out.riskTier, entry.risk_tier);
});

Deno.test("resilience: invalid LLM JSON falls back to raw KB", async () => {
  const entry = kbEntry();
  const out = await explainIngredient(entry, fixedLlm("not json at all"));
  assertEquals(out, rawKbToIngredient(entry));
});

Deno.test("resilience: an LLM that throws falls back to raw KB", async () => {
  const entry = kbEntry();
  const throwing: LlmClient = { complete: () => Promise.reject(new Error("boom")) };
  const out = await explainIngredient(entry, throwing);
  assertEquals(out, rawKbToIngredient(entry));
});

// ---------------------------------------------------------------------------
// applyRewrite unit + helpers
// ---------------------------------------------------------------------------

Deno.test("applyRewrite uses the rewrite only for present KB fields", () => {
  const entry = kbEntry({ safety: null });
  const out = applyRewrite(entry, {
    what: "New what",
    whyUsed: "New why",
    safety: "sneaky",
  });
  assertEquals(out.what, "New what");
  assertEquals(out.whyUsed, "New why");
  assertEquals(out.safety, null, "safety was null in KB → stays null");
});

Deno.test("applyRewrite keeps KB text when the rewrite is empty", () => {
  const entry = kbEntry();
  const out = applyRewrite(entry, { what: "", whyUsed: "   ", safety: undefined });
  assertEquals(out.what, entry.what);
  assertEquals(out.whyUsed, entry.why_used);
  assertEquals(out.safety, entry.safety);
});

Deno.test("toIngredientId slugifies to the OFF tag convention", () => {
  assertEquals(toIngredientId("Palm Oil"), "en:palm-oil");
  assertEquals(toIngredientId("  Wheat Flour  "), "en:wheat-flour");
  assertEquals(toIngredientId("Sugar"), "en:sugar");
});

// ---------------------------------------------------------------------------
// (f) seed integrity
// ---------------------------------------------------------------------------

Deno.test("seed integrity: every additives_risk entry has a matching KB entry, same tier", () => {
  const risk = additivesRisk as unknown as Record<string, { tier?: string }>;
  const byId = new Map(SEED_ENTRIES.map((e) => [e.id, e]));
  let additiveCount = 0;
  for (const [id, value] of Object.entries(risk)) {
    if (id === "_meta") continue;
    additiveCount++;
    const entry = byId.get(id);
    assert(entry, `additive ${id} missing from KB seed`);
    assertEquals(entry!.risk_tier, value.tier, `tier mismatch for ${id}`);
    assert(entry!.sources.length > 0, `additive ${id} has no sources`);
    assertEquals(entry!.kb_version, KB_VERSION);
  }
  assert(additiveCount >= 50, "expected the full additive table");
  assert(
    SEED_ENTRIES.length > additiveCount,
    "seed must also include common non-additive ingredients",
  );
});

Deno.test("seed integrity: BANNED_WORDS list is non-empty and lowercase", () => {
  assert(BANNED_WORDS.length > 0);
  for (const w of BANNED_WORDS) assertEquals(w, w.toLowerCase());
});
