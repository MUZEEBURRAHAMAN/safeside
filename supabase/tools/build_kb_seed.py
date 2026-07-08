#!/usr/bin/env python3
"""Regenerate the ingredient KB seed from the scoring additive table.

The ingredient knowledge base (docs/AI_INGREDIENT_EXPLANATION.md §3) has ONE
non-negotiable link to the scorer: for every additive, `risk_tier` MUST equal
the tier in supabase/functions/_shared/scoring/additives_risk.json, and the
regulatory sources MUST be reused verbatim. This script derives the additive
KB entries directly from that table so the two can never drift, then appends a
curated set of common non-additive ingredients (sugar, salt, oils, flours, …).

Nothing here fabricates science:
  - Additive `risk_tier`, `safety` (the regulatory `reason`), and `sources`
    are copied straight from additives_risk.json.
  - The plain-language `what` / `why_used` / `found_in` are FUNCTIONAL
    descriptions (what the ingredient does in food), chosen from category
    templates or per-id overrides. They make no health claims.
  - Common-ingredient entries are hand-vetted with named USDA / WHO / EFSA
    sources. Never add an entry without a real, named source.

Usage:
    python3 supabase/tools/build_kb_seed.py            # write the seed
    python3 supabase/tools/build_kb_seed.py --check     # verify it is in sync

Stdlib only. Run from anywhere; paths are resolved relative to this file.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

KB_VERSION = "1.0"
CONFIDENCE = "high"

ROOT = Path(__file__).resolve().parents[1]  # .../supabase
ADDITIVES_RISK = ROOT / "functions" / "_shared" / "scoring" / "additives_risk.json"
SEED_OUT = ROOT / "functions" / "_shared" / "kb" / "ingredient_kb_seed.json"

# ---------------------------------------------------------------------------
# Additive category templates — FUNCTIONAL descriptions only (no health claims).
# Matched against the additive name + regulatory `reason` text.
# ---------------------------------------------------------------------------
CATEGORY_TEMPLATES = {
    "color": {
        "what": "A colour used in food.",
        "why_used": "Adds or restores colour so a product looks consistent.",
        "found_in": ["sweets", "soft drinks", "coloured snacks", "desserts"],
    },
    "sweetener": {
        "what": "A sweetener used in place of some or all sugar.",
        "why_used": "Adds sweetness with little or no sugar and few or no calories.",
        "found_in": ["diet soft drinks", "sugar-free foods", "tabletop sweeteners"],
    },
    "preservative": {
        "what": "A preservative.",
        "why_used": "Helps food keep longer by slowing spoilage from microbes.",
        "found_in": ["soft drinks", "sauces", "baked goods", "cured foods"],
    },
    "antioxidant": {
        "what": "An antioxidant.",
        "why_used": "Slows fats and oils from going rancid, protecting flavour.",
        "found_in": ["oils", "snacks", "spreads", "processed meats"],
    },
    "emulsifier": {
        "what": "An emulsifier.",
        "why_used": "Helps oil and water mix and stay smoothly blended.",
        "found_in": ["spreads", "sauces", "ice cream", "baked goods"],
    },
    "thickener": {
        "what": "A thickener or gelling agent.",
        "why_used": "Thickens or sets the texture of a food.",
        "found_in": ["desserts", "dairy", "sauces", "jams"],
    },
    "acid": {
        "what": "A food acid.",
        "why_used": "Adjusts acidity or adds a tart taste; can also help preserve.",
        "found_in": ["soft drinks", "sweets", "preserves", "sauces"],
    },
    "phosphate": {
        "what": "A phosphate used as an additive.",
        "why_used": "Regulates acidity, raises baked goods, or holds moisture.",
        "found_in": ["colas", "processed cheese", "baked goods", "processed meats"],
    },
    "flavour_enhancer": {
        "what": "A flavour enhancer.",
        "why_used": "Boosts the savoury (umami) taste of a food.",
        "found_in": ["savoury snacks", "seasonings", "soups", "ready meals"],
    },
    "raising_agent": {
        "what": "A raising agent.",
        "why_used": "Releases gas so baked goods rise.",
        "found_in": ["baked goods", "self-raising flour", "cake mixes"],
    },
    "mineral": {
        "what": "A mineral used in food.",
        "why_used": "Adds firmness, adjusts acidity, or provides a mineral.",
        "found_in": ["supplemented foods", "baked goods", "canned vegetables"],
    },
    "flour_treatment": {
        "what": "A flour treatment agent.",
        "why_used": "Was used to strengthen dough and speed bread-making.",
        "found_in": ["some breads and flours in jurisdictions that still allow it"],
    },
    "humectant": {
        "what": "A humectant.",
        "why_used": "Holds moisture so foods stay soft.",
        "found_in": ["soft baked goods", "confectionery", "chewing gum"],
    },
    "generic": {
        "what": "A food additive.",
        "why_used": "Serves a technical role such as texture, colour, or shelf life.",
        "found_in": ["a range of packaged foods"],
    },
}


def classify_additive(name: str, reason: str) -> str:
    """Pick a category template key from the additive name + regulatory reason."""
    text = f"{name} {reason}".lower()
    # Order matters: most specific first.
    if "flavour enhancer" in text or "glutamat" in text or "umami" in text:
        return "flavour_enhancer"
    if "sweetener" in text or "aspartame" in text or "sucralose" in text or "acesulfame" in text:
        return "sweetener"
    if "flour treatment" in text or "bromate" in text:
        return "flour_treatment"
    if "phosphate" in text or "phosphoric" in text or "diphosphate" in text:
        return "phosphate"
    if "raising" in text or ("carbonate" in text and "baking" in text):
        return "raising_agent"
    if "emulsifier" in text or "lecithin" in text or "polysorbate" in text or "mono- and diglyceride" in text:
        return "emulsifier"
    if ("thickener" in text or "gelling" in text or "gum" in text or "pectin" in text
            or "agar" in text or "carrageenan" in text or "cellulose" in text):
        return "thickener"
    if "antioxidant" in text or "ascorbic" in text or "tocopherol" in text or "bha" in text or "bht" in text:
        return "antioxidant"
    if "preservative" in text or "sorbate" in text or "benzoate" in text or "nitrite" in text \
            or "nitrate" in text or "sulph" in text or "sulf" in text:
        return "preservative"
    if "colour" in text or "color" in text or "pigment" in text or "caramel" in text:
        return "color"
    if "humectant" in text or "glycerol" in text:
        return "humectant"
    if "acid" in text and "amino" not in text:
        return "acid"
    if "calcium carbonate" in text or "mineral" in text or "chalk" in text:
        return "mineral"
    return "generic"


# Per-id enrichment for additives where a well-established, sourced audience
# note or misconception is worth surfacing. Health notes only (not dietary
# preference). Everything else is left empty rather than guessed.
ADDITIVE_OVERRIDES: dict[str, dict] = {
    "en:e102": {"who_should_avoid": []},
    "en:e120": {
        "who_should_avoid": ["people with a known carmine or cochineal sensitivity"],
    },
    "en:e150d": {
        "what": "A caramel colour (the sulphite ammonia type).",
        "why_used": "Adds a brown colour, most familiar from colas.",
    },
    "en:e171": {
        "what": "A white mineral colour (titanium dioxide).",
        "why_used": "Makes foods and coatings look bright white or opaque.",
    },
    "en:e211": {
        "who_should_avoid": [],
        "misconceptions": [
            "The benzene concern applies only to some drinks that also contain vitamin C, not to sodium benzoate in general",
        ],
    },
    "en:e220": {
        "what": "Sulphur dioxide, a preservative and antioxidant.",
        "who_should_avoid": ["people who are sensitive to sulphites, including some people with asthma"],
    },
    "en:e249": {"what": "A curing salt (potassium nitrite) for processed meats."},
    "en:e250": {"what": "A curing salt (sodium nitrite) for processed meats."},
    "en:e321": {
        "misconceptions": [
            "IARC and animal-study findings are about high doses; regulators set intake limits well below those levels",
        ],
    },
    "en:e320": {
        "misconceptions": [
            "The 'possibly carcinogenic' label reflects high-dose animal data; typical dietary intake stays below the regulatory limit",
        ],
    },
    "en:e621": {
        "who_should_avoid": ["people advised to limit sodium"],
        "misconceptions": [
            "A specific 'MSG sensitivity' has not been confirmed in controlled blind studies",
            "Glutamate is a normal part of many everyday protein-rich foods",
        ],
    },
    "en:e951": {
        "who_should_avoid": ["people with phenylketonuria (PKU), because it contains phenylalanine"],
        "misconceptions": [
            "At normal intakes it has not been shown to cause the health harms sometimes claimed online",
        ],
    },
    "en:e950": {
        "misconceptions": [
            "Regulators set an intake limit that typical use stays within; the WHO advice is about relying on sweeteners for weight loss, not about safety at normal intakes",
        ],
    },
    "en:e955": {
        "misconceptions": [
            "The WHO advice is about using sweeteners for weight management, not a finding that normal intakes are harmful",
        ],
    },
    "en:e924": {
        "who_should_avoid": [],
        "misconceptions": [
            "It is already withdrawn from food use in the EU, UK, and Canada; where still allowed, limits apply",
        ],
    },
    "en:e407": {
        "misconceptions": [
            "Research on gut effects is ongoing; regulators kept only a temporary intake limit while asking for more studies",
        ],
    },
}


def build_additive_entries(risk_table: dict) -> list[dict]:
    entries: list[dict] = []
    for key, value in risk_table.items():
        if key == "_meta":
            continue
        name = value["name"]
        e_number = value.get("eNumber", "")
        reason = value.get("reason", "")
        tier = value["tier"]
        category = classify_additive(name, reason)
        template = CATEGORY_TEMPLATES[category]

        names = [name]
        if e_number and e_number not in names:
            names.append(e_number)

        entry = {
            "id": key,
            "names": names,
            "what": template["what"],
            "why_used": template["why_used"],
            # `safety` and `sources` come verbatim from the scoring table —
            # the single source of truth for regulatory claims.
            "safety": reason,
            "risk_tier": tier,
            "who_should_avoid": [],
            "misconceptions": [],
            "found_in": list(template["found_in"]),
            "sources": value.get("sources", []),
            "confidence": CONFIDENCE,
            "last_reviewed": value.get("lastReviewed", "2026-07"),
            "kb_version": KB_VERSION,
        }
        overrides = ADDITIVE_OVERRIDES.get(key, {})
        entry.update(overrides)
        entries.append(entry)
    return entries


# ---------------------------------------------------------------------------
# Common non-additive ingredients — hand-vetted, every entry sourced.
# Language is neutral, dose-aware, and free of the banned fear words.
# ---------------------------------------------------------------------------
USDA = {"name": "USDA FoodData Central", "url": "https://fdc.nal.usda.gov/"}

COMMON_INGREDIENTS: list[dict] = [
    {
        "id": "en:water",
        "names": ["Water", "Aqua"],
        "what": "Plain water.",
        "why_used": "Acts as a base or carrier and adjusts consistency.",
        "safety": "Water is an essential nutrient with no intake concern in food.",
        "found_in": ["drinks", "soups", "sauces", "many processed foods"],
        "sources": [USDA],
    },
    {
        "id": "en:sugar",
        "names": ["Sugar", "Sucrose"],
        "what": "Sugar (mostly sucrose) that adds sweetness and energy.",
        "why_used": "Adds sweetness and bulk, helps browning, and can help preserve foods like jam.",
        "safety": "Sugar is safe as a food; the WHO suggests keeping free sugars below 10% of daily energy, and ideally 5%, mainly to protect teeth and help manage weight.",
        "who_should_avoid": ["people managing diabetes may want to watch total sugars"],
        "misconceptions": ["The health guidance is about how much sugar we eat, not that any sugar is harmful in itself"],
        "found_in": ["soft drinks", "sweets", "baked goods", "cereals"],
        "sources": [
            {"name": "WHO guideline: sugars intake for adults and children, 2015", "url": "https://www.who.int/publications/i/item/9789241549028"},
            USDA,
        ],
    },
    {
        "id": "en:salt",
        "names": ["Salt", "Sodium chloride"],
        "what": "Sodium chloride — the mineral we know as table salt.",
        "why_used": "Adds flavour and, in many foods, helps preserve them and shape texture.",
        "safety": "Salt is safe, but most people eat more sodium than health bodies suggest; the WHO recommends limiting sodium to help manage blood pressure.",
        "who_should_avoid": ["people advised to limit sodium, for example for high blood pressure"],
        "misconceptions": ["Sea salt and pink salt are still mostly sodium chloride, like ordinary table salt"],
        "found_in": ["most savoury packaged foods", "bread", "snacks", "sauces"],
        "sources": [
            {"name": "WHO guideline: sodium intake for adults and children, 2012", "url": "https://www.who.int/publications/i/item/9789241504836"},
        ],
    },
    {
        "id": "en:palm-oil",
        "names": ["Palm oil", "Palm fat"],
        "what": "A vegetable oil pressed from the fruit of the oil palm.",
        "why_used": "Gives a smooth texture and long shelf life and stays solid at room temperature.",
        "safety": "Palm oil is safe to eat; it is high in saturated fat, which health bodies suggest limiting to support heart health.",
        "who_should_avoid": ["people advised to limit saturated fat"],
        "misconceptions": ["Concerns about palm oil centre on saturated fat and the environment, not on it being unsafe to eat"],
        "found_in": ["spreads", "chocolate", "baked goods", "margarine"],
        "sources": [
            {"name": "WHO guideline: saturated and trans-fatty acid intake, 2023", "url": "https://www.who.int/publications/i/item/9789240073630"},
            USDA,
        ],
    },
    {
        "id": "en:sunflower-oil",
        "names": ["Sunflower oil", "Sunflower seed oil"],
        "what": "A vegetable oil pressed from sunflower seeds.",
        "why_used": "Used for frying, texture, and as a neutral-tasting fat.",
        "safety": "Sunflower oil is safe to eat and is mostly unsaturated fat.",
        "found_in": ["fried foods", "spreads", "dressings", "snacks"],
        "sources": [USDA],
    },
    {
        "id": "en:rapeseed-oil",
        "names": ["Rapeseed oil", "Canola oil"],
        "what": "A vegetable oil pressed from rapeseed (canola).",
        "why_used": "A neutral cooking oil used for frying, baking, and dressings.",
        "safety": "Rapeseed (canola) oil is safe to eat and is low in saturated fat.",
        "found_in": ["cooking oils", "spreads", "baked goods", "mayonnaise"],
        "sources": [USDA],
    },
    {
        "id": "en:olive-oil",
        "names": ["Olive oil"],
        "what": "An oil pressed from olives.",
        "why_used": "Used for cooking and dressings and for its flavour.",
        "safety": "Olive oil is safe to eat and is rich in unsaturated fat.",
        "found_in": ["dressings", "Mediterranean dishes", "spreads", "cooking oils"],
        "sources": [USDA],
    },
    {
        "id": "en:butter",
        "names": ["Butter"],
        "what": "A dairy fat churned from cream.",
        "why_used": "Adds flavour and richness and shapes texture in baking.",
        "safety": "Butter is safe to eat; it is high in saturated fat, which health bodies suggest limiting.",
        "who_should_avoid": ["people with a milk allergy", "people advised to limit saturated fat"],
        "found_in": ["baked goods", "spreads", "sauces", "pastries"],
        "sources": [
            {"name": "WHO guideline: saturated and trans-fatty acid intake, 2023", "url": "https://www.who.int/publications/i/item/9789240073630"},
            USDA,
        ],
    },
    {
        "id": "en:wheat-flour",
        "names": ["Wheat flour", "Flour", "Wheat"],
        "what": "Flour milled from wheat grain.",
        "why_used": "Forms the structure of breads, baked goods, and batters.",
        "safety": "Wheat flour is safe for most people; it contains gluten and is a common allergen.",
        "who_should_avoid": ["people with coeliac disease or a wheat allergy", "people avoiding gluten"],
        "found_in": ["bread", "pasta", "baked goods", "batters"],
        "sources": [USDA],
    },
    {
        "id": "en:maize-starch",
        "names": ["Maize starch", "Corn starch", "Cornflour"],
        "what": "Starch extracted from maize (corn).",
        "why_used": "Thickens sauces and adds structure or a light texture.",
        "safety": "Maize starch is a safe, common food ingredient.",
        "found_in": ["sauces", "soups", "baked goods", "custards"],
        "sources": [USDA],
    },
    {
        "id": "en:rice",
        "names": ["Rice", "Rice flour"],
        "what": "A cereal grain, sometimes milled into flour.",
        "why_used": "A staple carbohydrate; rice flour adds structure in gluten-free foods.",
        "safety": "Rice is a safe, widely eaten staple grain.",
        "found_in": ["rice dishes", "gluten-free foods", "cereals", "snacks"],
        "sources": [USDA],
    },
    {
        "id": "en:oat",
        "names": ["Oats", "Oat", "Oat flakes"],
        "what": "A cereal grain, often rolled into flakes.",
        "why_used": "A staple grain used in cereals and baking; a source of fibre.",
        "safety": "Oats are a safe whole grain and a source of dietary fibre.",
        "who_should_avoid": ["some people with coeliac disease react to oats unless they are certified gluten-free"],
        "found_in": ["porridge", "cereals", "flapjacks", "baked goods"],
        "sources": [USDA],
    },
    {
        "id": "en:cocoa",
        "names": ["Cocoa", "Cocoa mass", "Cocoa solids", "Cocoa powder"],
        "what": "Solids from the cocoa bean.",
        "why_used": "Gives chocolate flavour and colour.",
        "safety": "Cocoa is a safe food ingredient; it naturally contains a small amount of caffeine.",
        "found_in": ["chocolate", "baked goods", "drinks", "desserts"],
        "sources": [USDA],
    },
    {
        "id": "en:cocoa-butter",
        "names": ["Cocoa butter"],
        "what": "The natural fat of the cocoa bean.",
        "why_used": "Gives chocolate its smooth texture and melt.",
        "safety": "Cocoa butter is safe to eat and is high in saturated fat.",
        "found_in": ["chocolate", "confectionery", "coatings"],
        "sources": [USDA],
    },
    {
        "id": "en:milk",
        "names": ["Milk", "Cow's milk"],
        "what": "Dairy milk.",
        "why_used": "Adds flavour, protein, and richness.",
        "safety": "Milk is a safe, nutritious food for most people; it is a common allergen and contains lactose.",
        "who_should_avoid": ["people with a milk allergy", "people with lactose intolerance"],
        "found_in": ["dairy products", "baked goods", "chocolate", "drinks"],
        "sources": [USDA],
    },
    {
        "id": "en:skimmed-milk-powder",
        "names": ["Skimmed milk powder", "Skim milk powder", "Nonfat dry milk"],
        "what": "Milk with the fat and water removed, dried to a powder.",
        "why_used": "Adds dairy solids, protein, and body without adding liquid.",
        "safety": "Skimmed milk powder is safe for most people; it is a milk product and a common allergen.",
        "who_should_avoid": ["people with a milk allergy", "people with lactose intolerance"],
        "found_in": ["chocolate", "baked goods", "ready meals", "beverages"],
        "sources": [USDA],
    },
    {
        "id": "en:whey",
        "names": ["Whey", "Whey powder", "Whey protein"],
        "what": "The protein-rich liquid left when milk is made into cheese, often dried.",
        "why_used": "Adds protein, flavour, and texture.",
        "safety": "Whey is safe for most people; it is a milk product and a common allergen.",
        "who_should_avoid": ["people with a milk allergy"],
        "found_in": ["chocolate", "baked goods", "protein products", "processed foods"],
        "sources": [USDA],
    },
    {
        "id": "en:egg",
        "names": ["Egg", "Eggs", "Whole egg", "Egg white", "Egg yolk"],
        "what": "Hen's egg or a part of it.",
        "why_used": "Binds, sets, and adds structure, richness, and colour.",
        "safety": "Eggs are a safe, nutritious food for most people; they are a common allergen.",
        "who_should_avoid": ["people with an egg allergy"],
        "found_in": ["baked goods", "pasta", "sauces", "mayonnaise"],
        "sources": [USDA],
    },
    {
        "id": "en:honey",
        "names": ["Honey"],
        "what": "A natural sweetener made by bees.",
        "why_used": "Adds sweetness and flavour.",
        "safety": "Honey is a form of sugar and safe for most people; it should not be given to infants under 12 months.",
        "who_should_avoid": ["infants under 12 months", "people managing diabetes may want to watch total sugars"],
        "misconceptions": ["Honey is still a sugar nutritionally, even though it is less processed than table sugar"],
        "found_in": ["cereals", "spreads", "drinks", "baked goods"],
        "sources": [USDA],
    },
    {
        "id": "en:glucose-syrup",
        "names": ["Glucose syrup", "Glucose-fructose syrup", "Corn syrup"],
        "what": "A liquid sugar made from starch, such as maize or wheat.",
        "why_used": "Adds sweetness, texture, and shelf life and stops crystals forming.",
        "safety": "Glucose syrup is a form of sugar; the WHO advice on limiting free sugars applies to it.",
        "who_should_avoid": ["people managing diabetes may want to watch total sugars"],
        "found_in": ["sweets", "soft drinks", "baked goods", "ice cream"],
        "sources": [
            {"name": "WHO guideline: sugars intake for adults and children, 2015", "url": "https://www.who.int/publications/i/item/9789241549028"},
            USDA,
        ],
    },
    {
        "id": "en:high-fructose-corn-syrup",
        "names": ["High-fructose corn syrup", "HFCS", "High fructose corn syrup"],
        "what": "A liquid sweetener made from corn starch with some glucose converted to fructose.",
        "why_used": "A cheap liquid sweetener that adds sweetness and shelf life, common in drinks.",
        "safety": "It is a form of sugar; the WHO advice on limiting free sugars applies to it as to other sugars.",
        "who_should_avoid": ["people managing diabetes may want to watch total sugars"],
        "misconceptions": ["The evidence treats it much like other added sugars; the concern is total added sugar, not this syrup uniquely"],
        "found_in": ["soft drinks", "sweets", "sauces", "baked goods"],
        "sources": [
            {"name": "WHO guideline: sugars intake for adults and children, 2015", "url": "https://www.who.int/publications/i/item/9789241549028"},
            USDA,
        ],
    },
    {
        "id": "en:yeast",
        "names": ["Yeast", "Baker's yeast"],
        "what": "A microorganism used to leaven bread and in fermentation.",
        "why_used": "Makes dough rise and adds flavour.",
        "safety": "Baker's yeast is a safe, common food ingredient.",
        "found_in": ["bread", "baked goods", "spreads", "fermented foods"],
        "sources": [USDA],
    },
]


def normalize_common(entries: list[dict]) -> list[dict]:
    """Fill defaults so every common-ingredient entry matches the KB schema."""
    out = []
    for e in entries:
        out.append({
            "id": e["id"],
            "names": e["names"],
            "what": e.get("what"),
            "why_used": e.get("why_used"),
            "safety": e.get("safety"),
            "risk_tier": e.get("risk_tier", "low"),
            "who_should_avoid": e.get("who_should_avoid", []),
            "misconceptions": e.get("misconceptions", []),
            "found_in": e.get("found_in", []),
            "sources": e.get("sources", []),
            "confidence": e.get("confidence", CONFIDENCE),
            "last_reviewed": e.get("last_reviewed", "2026-07"),
            "kb_version": KB_VERSION,
        })
    return out


def build_seed() -> dict:
    risk_table = json.loads(ADDITIVES_RISK.read_text())
    additives = build_additive_entries(risk_table)
    common = normalize_common(COMMON_INGREDIENTS)
    entries = additives + common
    entries.sort(key=lambda e: e["id"])
    return {
        "_meta": {
            "kb_version": KB_VERSION,
            "generated_by": "supabase/tools/build_kb_seed.py",
            "note": "Additive entries are derived from additives_risk.json (risk_tier + safety + sources copied verbatim). Do not hand-edit; run the script.",
            "count": len(entries),
        },
        "entries": entries,
    }


def serialize(seed: dict) -> str:
    return json.dumps(seed, indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the seed is in sync; exit 1 if not")
    args = parser.parse_args()

    seed = build_seed()
    rendered = serialize(seed)

    if args.check:
        if not SEED_OUT.exists():
            print(f"MISSING: {SEED_OUT}", file=sys.stderr)
            return 1
        current = SEED_OUT.read_text()
        if current != rendered:
            print("OUT OF SYNC: regenerate with `python3 supabase/tools/build_kb_seed.py`", file=sys.stderr)
            return 1
        print(f"OK: {seed['_meta']['count']} entries in sync")
        return 0

    SEED_OUT.parent.mkdir(parents=True, exist_ok=True)
    SEED_OUT.write_text(rendered)
    print(f"Wrote {seed['_meta']['count']} entries to {SEED_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
