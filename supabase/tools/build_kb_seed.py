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

KB_VERSION = "1.1"
CONFIDENCE = "high"

ROOT = Path(__file__).resolve().parents[1]  # .../supabase
ADDITIVES_RISK = ROOT / "functions" / "_shared" / "scoring" / "additives_risk.json"
SEED_OUT = ROOT / "functions" / "_shared" / "kb" / "ingredient_kb_seed.json"
SQL_OUT = ROOT / "migrations" / "20260708120000_kb_seed_v1_1.sql"

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
    "polyol": {
        "what": "A sugar alcohol (polyol) used as a sweetener.",
        "why_used": "Adds sweetness and bulk with fewer calories than sugar; also helps hold moisture.",
        "found_in": ["sugar-free sweets", "chewing gum", "sugar-free chocolate", "baked goods"],
    },
    "modified_starch": {
        "what": "A modified starch.",
        "why_used": "A starch treated so it thickens or stays stable during cooking, freezing, or storage.",
        "found_in": ["sauces", "soups", "ready meals", "desserts"],
    },
    "glazing": {
        "what": "A glazing agent.",
        "why_used": "Forms a shiny protective coating on the surface of a food.",
        "found_in": ["confectionery", "chocolate", "coated fruit", "supplements"],
    },
    "gas": {
        "what": "A food-grade gas.",
        "why_used": "Used to carbonate drinks or to protect packaged food by replacing oxygen.",
        "found_in": ["fizzy drinks", "packaged fresh foods", "bagged snacks"],
    },
    "anti_caking": {
        "what": "An anti-caking agent.",
        "why_used": "Keeps powders and granules free-flowing and stops them clumping.",
        "found_in": ["powdered foods", "seasonings", "grated cheese", "supplements"],
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
    # Polyols before the generic "sweetener" branch (they have bulk + calories).
    if "polyol" in text or "sugar alcohol" in text:
        return "polyol"
    if "sweetener" in text or "aspartame" in text or "sucralose" in text or "acesulfame" in text \
            or "stevia" in text or "steviol" in text:
        return "sweetener"
    # Modified starch before "phosphate" (e.g. "distarch phosphate" is a starch).
    if "starch" in text:
        return "modified_starch"
    if "glazing" in text or "shellac" in text or "beeswax" in text or "carnauba" in text \
            or "wax" in text:
        return "glazing"
    if "carbon dioxide" in text or "nitrogen" in text or "inert gas" in text \
            or "packaging gas" in text:
        return "gas"
    if "anti-caking" in text or "silicon dioxide" in text:
        return "anti_caking"
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
    "en:e150a": {
        "what": "A plain caramel colour (made by heating carbohydrates).",
        "why_used": "Adds a brown colour.",
    },
    "en:e150c": {
        "what": "An ammonia caramel colour.",
        "why_used": "Adds a brown colour, common in savoury foods and some drinks.",
    },
    "en:e150d": {
        "what": "A caramel colour (the sulphite ammonia type).",
        "why_used": "Adds a brown colour, most familiar from colas.",
    },
    "en:e172": {
        "what": "Iron-oxide mineral colours (yellow, red, black).",
        "why_used": "Add yellow, red, brown, or black colour.",
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
WHO_SUGARS = {
    "name": "WHO guideline: sugars intake for adults and children, 2015",
    "url": "https://www.who.int/publications/i/item/9789241549028",
}
WHO_SATFAT = {
    "name": "WHO guideline: saturated and trans-fatty acid intake, 2023",
    "url": "https://www.who.int/publications/i/item/9789240073630",
}
WHO_FORTIFICATION = {
    "name": "WHO guidelines on food fortification with micronutrients",
    "url": "https://www.who.int/publications/i/item/9241594012",
}
EFSA_DRV = {
    "name": "EFSA Dietary Reference Values for nutrients",
    "url": "https://www.efsa.europa.eu/en/topics/topic/dietary-reference-values",
}
EFSA_FLAVOURINGS = {
    "name": "EFSA information on food flavourings",
    "url": "https://www.efsa.europa.eu/en/topics/topic/flavourings",
}
EFSA_STARCH = {
    "name": "EFSA re-evaluation of modified starches as food additives",
    "url": "https://www.efsa.europa.eu/en/topics/topic/food-additives",
}

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
    {
        "id": "en:soybean-oil",
        "names": ["Soybean oil", "Soya oil", "Soya bean oil"],
        "what": "A vegetable oil pressed from soybeans.",
        "why_used": "A neutral cooking oil used for frying, baking, and dressings.",
        "safety": "Soybean oil is safe to eat and is mostly unsaturated fat.",
        "who_should_avoid": ["people with a soya allergy may want to check with a clinician, though refined soybean oil is usually tolerated"],
        "found_in": ["cooking oils", "dressings", "spreads", "processed foods"],
        "sources": [USDA],
    },
    {
        "id": "en:coconut-oil",
        "names": ["Coconut oil"],
        "what": "An oil pressed from coconut flesh.",
        "why_used": "Adds texture and stays solid at room temperature.",
        "safety": "Coconut oil is safe to eat; it is high in saturated fat, which health bodies suggest limiting.",
        "who_should_avoid": ["people advised to limit saturated fat"],
        "misconceptions": ["Claims that coconut oil is a uniquely healthy fat are not well supported; it is still high in saturated fat"],
        "found_in": ["baked goods", "spreads", "confectionery", "cooking oils"],
        "sources": [WHO_SATFAT, USDA],
    },
    {
        "id": "en:maize",
        "names": ["Maize", "Corn", "Sweetcorn"],
        "what": "A cereal grain (corn).",
        "why_used": "A staple grain eaten whole or milled and used as a base for many foods.",
        "safety": "Maize (corn) is a safe, widely eaten grain.",
        "found_in": ["cereals", "snacks", "tortillas", "canned vegetables"],
        "sources": [USDA],
    },
    {
        "id": "en:barley",
        "names": ["Barley", "Pearl barley"],
        "what": "A cereal grain.",
        "why_used": "A staple grain used in foods and to make malt.",
        "safety": "Barley is a safe whole grain; it contains gluten.",
        "who_should_avoid": ["people with coeliac disease or who avoid gluten"],
        "found_in": ["soups", "cereals", "malt", "bread"],
        "sources": [USDA],
    },
    {
        "id": "en:rye",
        "names": ["Rye", "Rye flour"],
        "what": "A cereal grain, often milled into flour.",
        "why_used": "Used in breads and crispbreads.",
        "safety": "Rye is a safe whole grain; it contains gluten.",
        "who_should_avoid": ["people with coeliac disease or who avoid gluten"],
        "found_in": ["rye bread", "crispbread", "cereals"],
        "sources": [USDA],
    },
    {
        "id": "en:potato-starch",
        "names": ["Potato starch"],
        "what": "Starch extracted from potatoes.",
        "why_used": "Thickens and binds and adds a light texture.",
        "safety": "Potato starch is a safe, common food ingredient.",
        "found_in": ["sauces", "baked goods", "gluten-free foods", "soups"],
        "sources": [USDA],
    },
    {
        "id": "en:modified-starch",
        "names": ["Modified starch", "Modified corn starch", "Modified maize starch", "Food starch modified"],
        "what": "A starch that has been physically or chemically treated.",
        "why_used": "Thickens or stabilises foods and stays stable during cooking, freezing, or storage.",
        "safety": "Modified starches are safe, common food ingredients; EFSA re-evaluated them and found no safety concern at reported uses.",
        "misconceptions": ["'Modified' here means the starch was processed to work better in food, not that it is genetically modified"],
        "found_in": ["sauces", "soups", "ready meals", "desserts"],
        "sources": [EFSA_STARCH, USDA],
    },
    {
        "id": "en:cream",
        "names": ["Cream", "Double cream", "Single cream"],
        "what": "The fat-rich part of milk.",
        "why_used": "Adds richness and texture.",
        "safety": "Cream is a safe dairy food; it is a milk product and is high in saturated fat.",
        "who_should_avoid": ["people with a milk allergy", "people advised to limit saturated fat"],
        "found_in": ["desserts", "sauces", "baked goods", "dairy products"],
        "sources": [WHO_SATFAT, USDA],
    },
    {
        "id": "en:cheese",
        "names": ["Cheese", "Cheddar", "Mozzarella"],
        "what": "A dairy food made by curdling milk.",
        "why_used": "Adds flavour, protein, and texture.",
        "safety": "Cheese is a safe, nutritious dairy food for most people; it is a milk product and can be high in salt and saturated fat.",
        "who_should_avoid": ["people with a milk allergy", "people advised to limit sodium or saturated fat"],
        "found_in": ["ready meals", "sandwiches", "pizza", "snacks"],
        "sources": [USDA],
    },
    {
        "id": "en:yogurt",
        "names": ["Yogurt", "Yoghurt"],
        "what": "A dairy food made by fermenting milk.",
        "why_used": "Adds flavour, protein, and a creamy texture.",
        "safety": "Yogurt is a safe, nutritious dairy food for most people; it is a milk product.",
        "who_should_avoid": ["people with a milk allergy"],
        "found_in": ["dairy aisle", "desserts", "drinks", "dips"],
        "sources": [USDA],
    },
    {
        "id": "en:soybean",
        "names": ["Soy", "Soya", "Soybeans", "Soya beans"],
        "what": "A legume (soybean) and foods made from it.",
        "why_used": "A plant protein used whole or as an ingredient in many foods.",
        "safety": "Soy is a safe, protein-rich food for most people; it is a common allergen.",
        "who_should_avoid": ["people with a soya allergy"],
        "found_in": ["tofu", "plant drinks", "meat alternatives", "processed foods"],
        "sources": [USDA],
    },
    {
        "id": "en:soy-protein",
        "names": ["Soy protein", "Soya protein", "Soy protein isolate", "Soya protein isolate"],
        "what": "Protein extracted from soybeans.",
        "why_used": "Adds protein and structure, often in meat alternatives.",
        "safety": "Soy protein is safe for most people; it is a common allergen.",
        "who_should_avoid": ["people with a soya allergy"],
        "found_in": ["meat alternatives", "protein products", "processed foods", "cereal bars"],
        "sources": [USDA],
    },
    {
        "id": "en:pea-protein",
        "names": ["Pea protein", "Pea protein isolate"],
        "what": "Protein extracted from peas.",
        "why_used": "Adds protein and structure, often in plant-based foods.",
        "safety": "Pea protein is a safe, plant-based protein.",
        "found_in": ["meat alternatives", "plant drinks", "protein products", "cereal bars"],
        "sources": [USDA],
    },
    {
        "id": "en:gelatin",
        "names": ["Gelatin", "Gelatine"],
        "what": "A protein set from animal collagen.",
        "why_used": "Sets and thickens foods into a gel.",
        "safety": "Gelatin is a safe, common food ingredient; it comes from animals, so it is not suitable for vegetarians or vegans.",
        "who_should_avoid": ["vegetarians and vegans, because it is an animal product"],
        "found_in": ["jelly", "gummy sweets", "desserts", "some yogurts"],
        "sources": [USDA],
    },
    {
        "id": "en:fructose",
        "names": ["Fructose", "Fruit sugar"],
        "what": "A simple sugar found naturally in fruit and honey.",
        "why_used": "Adds sweetness.",
        "safety": "Fructose is a form of sugar; the WHO advice on limiting free sugars applies to it when it is added to foods.",
        "who_should_avoid": ["people managing diabetes may want to watch total sugars"],
        "found_in": ["soft drinks", "sweets", "baked goods", "sauces"],
        "sources": [WHO_SUGARS, USDA],
    },
    {
        "id": "en:dextrose",
        "names": ["Dextrose", "Glucose", "Grape sugar"],
        "what": "A simple sugar (glucose), often made from maize.",
        "why_used": "Adds sweetness and energy and is used in baking and sports foods.",
        "safety": "Dextrose (glucose) is a form of sugar; the WHO advice on limiting free sugars applies to it.",
        "who_should_avoid": ["people managing diabetes may want to watch total sugars"],
        "found_in": ["sports drinks", "sweets", "baked goods", "processed foods"],
        "sources": [WHO_SUGARS, USDA],
    },
    {
        "id": "en:maltodextrin",
        "names": ["Maltodextrin"],
        "what": "A carbohydrate made from starch such as maize or wheat.",
        "why_used": "Adds bulk or texture, carries flavours, and gives quick energy.",
        "safety": "Maltodextrin is a safe, common food ingredient; it raises blood glucose quickly, like other starches and sugars.",
        "who_should_avoid": ["people managing diabetes may want to note it affects blood glucose"],
        "found_in": ["sports foods", "sauces", "snacks", "processed foods"],
        "sources": [USDA],
    },
    {
        "id": "en:molasses",
        "names": ["Molasses", "Treacle", "Blackstrap molasses"],
        "what": "A thick syrup left from refining sugar.",
        "why_used": "Adds sweetness, colour, and a strong flavour.",
        "safety": "Molasses is a form of sugar; the WHO advice on limiting free sugars applies to it.",
        "who_should_avoid": ["people managing diabetes may want to watch total sugars"],
        "found_in": ["baked goods", "sauces", "cereals", "confectionery"],
        "sources": [WHO_SUGARS, USDA],
    },
    {
        "id": "en:vinegar",
        "names": ["Vinegar", "Spirit vinegar", "White vinegar"],
        "what": "A sour liquid made by fermenting alcohol into acetic acid.",
        "why_used": "Adds a tart flavour and helps preserve foods like pickles.",
        "safety": "Vinegar is a safe, common food ingredient.",
        "found_in": ["dressings", "sauces", "pickles", "condiments"],
        "sources": [USDA],
    },
    {
        "id": "en:baking-powder",
        "names": ["Baking powder"],
        "what": "A raising-agent blend, usually a carbonate plus an acid salt.",
        "why_used": "Releases gas so baked goods rise.",
        "safety": "Baking powder is a safe, common baking ingredient.",
        "found_in": ["cakes", "biscuits", "self-raising products", "batters"],
        "sources": [USDA],
    },
    {
        "id": "en:tomato-paste",
        "names": ["Tomato paste", "Tomato purée", "Tomato puree", "Concentrated tomato"],
        "what": "Tomatoes cooked down and concentrated.",
        "why_used": "Adds tomato flavour, colour, and body.",
        "safety": "Tomato paste is a safe food made from tomatoes.",
        "found_in": ["sauces", "soups", "pizza", "ready meals"],
        "sources": [USDA],
    },
    {
        "id": "en:natural-flavouring",
        "names": ["Natural flavouring", "Natural flavour", "Flavouring", "Flavour", "Flavourings"],
        "what": "Flavour ingredients used in small amounts to give or boost taste.",
        "why_used": "Adds or rounds out the taste of a food.",
        "safety": "Flavourings are used in very small amounts and are regulated for safety; their specific identities are often not listed on the label.",
        "misconceptions": ["'Natural flavouring' means the flavour comes from a natural source; it does not tell you the exact ingredient"],
        "found_in": ["soft drinks", "snacks", "dairy", "many processed foods"],
        "sources": [EFSA_FLAVOURINGS],
    },
    {
        "id": "en:folic-acid",
        "names": ["Folic acid", "Folate", "Vitamin B9"],
        "what": "A B vitamin (folate) added to foods.",
        "why_used": "Fortifies foods to help people meet their folate needs.",
        "safety": "Folic acid is safe at the levels used to fortify foods; it is especially important before and during early pregnancy.",
        "found_in": ["fortified flour", "breakfast cereals", "bread"],
        "sources": [WHO_FORTIFICATION, EFSA_DRV],
    },
    {
        "id": "en:iron",
        "names": ["Iron", "Ferrous fumarate", "Ferrous sulphate", "Reduced iron"],
        "what": "A mineral added to fortify foods.",
        "why_used": "Fortifies foods to help people meet their iron needs.",
        "safety": "Added iron is safe at the levels used to fortify foods; iron is an essential mineral.",
        "found_in": ["fortified cereals", "fortified flour", "plant drinks"],
        "sources": [WHO_FORTIFICATION, USDA],
    },
    {
        "id": "en:calcium",
        "names": ["Calcium", "Added calcium", "Calcium (fortified)"],
        "what": "A mineral added to fortify foods.",
        "why_used": "Fortifies foods such as plant drinks and flour with calcium.",
        "safety": "Added calcium is safe at the levels used to fortify foods; calcium is an essential mineral for bones.",
        "found_in": ["plant drinks", "fortified flour", "breakfast cereals"],
        "sources": [WHO_FORTIFICATION, EFSA_DRV],
    },
    {
        "id": "en:niacin",
        "names": ["Niacin", "Vitamin B3", "Nicotinamide"],
        "what": "A B vitamin added to foods.",
        "why_used": "Fortifies foods to help people meet their niacin needs.",
        "safety": "Niacin is safe at the levels used to fortify foods; it is an essential B vitamin.",
        "found_in": ["fortified flour", "breakfast cereals", "bread"],
        "sources": [EFSA_DRV, USDA],
    },
    {
        "id": "en:vitamin-d",
        "names": ["Vitamin D", "Vitamin D3", "Cholecalciferol"],
        "what": "A vitamin added to fortify some foods.",
        "why_used": "Fortifies foods such as spreads and cereals with vitamin D.",
        "safety": "Vitamin D is safe at the levels used to fortify foods; it supports bone health.",
        "found_in": ["fortified spreads", "breakfast cereals", "plant drinks"],
        "sources": [EFSA_DRV, USDA],
    },
    {
        "id": "en:vitamin-c",
        "names": ["Vitamin C", "L-ascorbic acid", "Ascorbic acid (added)"],
        "what": "A vitamin added to foods, also used as an antioxidant.",
        "why_used": "Fortifies foods and protects colour and flavour.",
        "safety": "Vitamin C is safe at the levels used in foods; it is an essential vitamin.",
        "misconceptions": ["As an added antioxidant it can appear on labels as E300; it is the same vitamin C"],
        "found_in": ["fortified drinks", "cereals", "juices"],
        "sources": [EFSA_DRV, USDA],
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


# ---------------------------------------------------------------------------
# SQL upsert migration — generated from the same seed so it can never drift.
# ---------------------------------------------------------------------------
def _sql_str(v) -> str:
    if v is None:
        return "null"
    return "'" + str(v).replace("'", "''") + "'"


def _sql_text_array(items) -> str:
    if not items:
        return "array[]::text[]"
    return "array[" + ", ".join(_sql_str(i) for i in items) + "]::text[]"


def _sql_jsonb(obj) -> str:
    return "'" + json.dumps(obj, ensure_ascii=False).replace("'", "''") + "'::jsonb"


def build_sql(seed: dict) -> str:
    entries = seed["entries"]
    rows = []
    for e in entries:
        rows.append(
            "  (" + ", ".join([
                _sql_str(e["id"]),
                _sql_text_array(e["names"]),
                _sql_str(e["what"]),
                _sql_str(e["why_used"]),
                _sql_str(e["safety"]),
                _sql_str(e["risk_tier"]),
                _sql_text_array(e["who_should_avoid"]),
                _sql_text_array(e["misconceptions"]),
                _sql_text_array(e["found_in"]),
                _sql_jsonb(e["sources"]),
                _sql_str(e["confidence"]),
                _sql_str(e["last_reviewed"]),
                _sql_str(e["kb_version"]),
            ]) + ")"
        )
    header = (
        "-- =============================================================================\n"
        f"-- GENERATED by supabase/tools/build_kb_seed.py --sql — do not hand-edit.\n"
        f"-- Upserts the full ingredient KB seed (kb_version {KB_VERSION}, "
        f"{len(entries)} entries) into ingredient_kb.\n"
        "-- Apply AFTER 20260708000000_ingredient_kb.sql (which creates the table + enums).\n"
        "-- Idempotent: re-running upserts by id and refreshes every field.\n"
        "-- Additive risk_tier values equal supabase/functions/_shared/scoring/\n"
        "-- additives_risk.json (one source of truth). Regenerate with:\n"
        "--   python3 supabase/tools/build_kb_seed.py\n"
        "-- =============================================================================\n\n"
    )
    body = (
        "insert into ingredient_kb\n"
        "  (id, names, what, why_used, safety, risk_tier, who_should_avoid,\n"
        "   misconceptions, found_in, sources, confidence, last_reviewed, kb_version)\n"
        "values\n"
        + ",\n".join(rows)
        + "\non conflict (id) do update set\n"
        "  names            = excluded.names,\n"
        "  what             = excluded.what,\n"
        "  why_used         = excluded.why_used,\n"
        "  safety           = excluded.safety,\n"
        "  risk_tier        = excluded.risk_tier,\n"
        "  who_should_avoid = excluded.who_should_avoid,\n"
        "  misconceptions   = excluded.misconceptions,\n"
        "  found_in         = excluded.found_in,\n"
        "  sources          = excluded.sources,\n"
        "  confidence       = excluded.confidence,\n"
        "  last_reviewed    = excluded.last_reviewed,\n"
        "  kb_version       = excluded.kb_version,\n"
        "  updated_at       = now();\n"
    )
    return header + body


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the seed + SQL are in sync; exit 1 if not")
    args = parser.parse_args()

    seed = build_seed()
    rendered = serialize(seed)
    sql = build_sql(seed)

    if args.check:
        if not SEED_OUT.exists():
            print(f"MISSING: {SEED_OUT}", file=sys.stderr)
            return 1
        if SEED_OUT.read_text() != rendered:
            print("OUT OF SYNC: regenerate with `python3 supabase/tools/build_kb_seed.py`", file=sys.stderr)
            return 1
        if not SQL_OUT.exists() or SQL_OUT.read_text() != sql:
            print("OUT OF SYNC (SQL): regenerate with `python3 supabase/tools/build_kb_seed.py`", file=sys.stderr)
            return 1
        print(f"OK: {seed['_meta']['count']} entries in sync (JSON + SQL)")
        return 0

    SEED_OUT.parent.mkdir(parents=True, exist_ok=True)
    SEED_OUT.write_text(rendered)
    SQL_OUT.parent.mkdir(parents=True, exist_ok=True)
    SQL_OUT.write_text(sql)
    print(f"Wrote {seed['_meta']['count']} entries to {SEED_OUT}")
    print(f"Wrote upsert migration to {SQL_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
