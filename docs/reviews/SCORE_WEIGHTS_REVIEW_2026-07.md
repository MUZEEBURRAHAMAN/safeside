# SafeSide — Scoring Weights & Calibration Review

**For:** the founder's dietitian / nutrition reviewer
**Prepared:** 2026-07 (Chunk 4, Task 6)
**Score version under review:** `1.1.0` (`supabase/functions/_shared/scoring/engine.ts`)
**Additive risk table version:** `1.1` (last reviewed 2026-07)

> This is a **read-only export** of the live scoring surface so a qualified reviewer
> can sanity-check the weights, the additive risk tiers, and the 50-product
> calibration set. **No code or weights were changed to produce this file.** If the
> reviewer wants a change, see *Sign-off & standing instruction* at the bottom.

## How the score is built (plain language)

Every score is **computed deterministically from data** — the LLM never calculates
any number (it only ever explains). The composite is a weighted blend of three
sub-scores, each 0–100, then rounded half-up to a 0–100 score and bucketed into a
band. Language is deliberately neutral (no "good/bad/toxic") and the design is
ED-safe: no single additive can tank a score.

**Composite = 0.50 × Processing + 0.35 × Nutrition + 0.15 × Additives**

| Component | Weight | Source of the sub-score |
|---|---|---|
| Processing | **0.50** | NOVA group (1–4) |
| Nutrition | **0.35** | Nutri-Score grade (A–E) |
| Additives | **0.15** | Curated additive risk tiers (below) |

When only one of NOVA / Nutri-Score is available, the remaining weights are
**renormalized to sum to 1** and confidence drops to "limited". When BOTH are
missing (e.g. an OCR-only label), the product is band **"unknown"** with no numeric
score — we never fabricate a precise number from thin data.

### NOVA → Processing sub-score
| NOVA group | Meaning | Sub-score |
|---|---|---|
| 1 | Unprocessed / minimally processed | 100 |
| 2 | Processed culinary ingredient | 80 |
| 3 | Processed food | 55 |
| 4 | Ultra-processed food | 20 |

### Nutri-Score → Nutrition sub-score
| Nutri-Score | Sub-score |
|---|---|
| A | 90 |
| B | 70 |
| C | 50 |
| D | 30 |
| E | 12 |

### Additives → Additives sub-score
Start at 100; penalties are applied **per tier**, "first / each additional", then
**floored at 30** so a pile of additives can never dominate the score.

| Tier | First additive | Each additional | Rationale |
|---|---|---|---|
| Low | −0 | −0 | Broadly recognized as safe at typical intakes |
| Moderate | −6 | −3 | Regulatory intake caution exists (ADI set / labeling) |
| Higher | −15 | −8 | Restricted/withdrawn in a major jurisdiction, or under active re-review |

Floor: **30**. Bands: score ≥ 75 → **high** ("Lower-processed"), 45–74 → **mid**
("Moderately processed"), < 45 → **low** ("Higher-processed"), no data → **unknown**.

## Band thresholds
| Band | Score range |
|---|---|
| high | 75–100 |
| mid | 45–74 |
| low | 0–44 |
| unknown | no numeric score (insufficient data) |

## Additive risk tiers (124 entries)

Tiers reflect **risk** (real-world dietary exposure vs regulatory intake limits),
not theoretical hazard. Every entry cites a named regulatory review (EFSA / FDA /
JECFA / IARC) — never blogs or single cherry-picked studies. Additives **not** in
this table are scored **low** and flagged "not yet reviewed" — absence of review is
never treated as evidence of concern.

**Distribution:** 84 low · 35 moderate · 5 higher.

| E-number | Name | Tier | Reason (with regulatory source) |
|---|---|---|---|
| E100 | Curcumin | low | Natural turmeric color; EFSA set an ADI and typical dietary exposure stays within it. |
| E101 | Riboflavin (vitamin B2) | low | A B vitamin used as a yellow color; EFSA found no safety concern at reported uses. |
| E102 | Tartrazine | moderate | Azo color with an EFSA ADI; foods containing it in the EU must carry a note about possible effects on activity and attention in children. |
| E104 | Quinoline yellow | moderate | EFSA lowered its ADI in 2009 and EU labelling rules for certain colors apply; not authorized for food in the US. |
| E110 | Sunset yellow FCF | moderate | Azo color; EFSA revised its ADI in 2014 and EU child-activity labelling rules apply. |
| E120 | Cochineal / carminic acid (carmine) | moderate | EFSA maintained the ADI in 2015; rare hypersensitivity reactions are documented, so people with known sensitivity may want to check for it. |
| E122 | Azorubine / carmoisine | moderate | Azo color with an EFSA ADI; EU child-activity labelling rules apply and it is not authorized in the US. |
| E124 | Ponceau 4R | moderate | EFSA lowered its ADI in 2009; EU child-activity labelling rules apply and it is not authorized in the US. |
| E127 | Erythrosine (Red 3) | higher | The US FDA revoked its authorization for foods in January 2025 based on findings in laboratory animals; it remains permitted in limited uses elsewhere. |
| E129 | Allura red AC | moderate | Azo color with an EFSA ADI; EU child-activity labelling rules apply. |
| E133 | Brilliant blue FCF | low | EFSA set an ADI and estimated dietary exposure stays below it for all population groups. |
| E140 | Chlorophylls | low | A green plant-derived colour; EFSA re-evaluated it as a food colour and placed no numeric intake limit on it. |
| E1412 | Distarch phosphate | low | A modified starch used as a thickener and stabiliser; EFSA re-evaluated the modified starches and found no safety concern at reported uses. |
| E1414 | Acetylated distarch phosphate | low | A modified starch used as a thickener and stabiliser; EFSA re-evaluated the modified starches and found no safety concern at reported uses. |
| E1422 | Acetylated distarch adipate | low | A modified starch used as a thickener and stabiliser; EFSA re-evaluated the modified starches and found no safety concern at reported uses. |
| E1442 | Hydroxypropyl distarch phosphate | low | A modified starch used as a thickener and stabiliser; EFSA re-evaluated the modified starches and found no safety concern at reported uses. |
| E150a | Plain caramel | low | A plain caramel colour made by heating carbohydrates; EFSA set a group ADI for caramel colours that plain caramel stays within. |
| E150c | Ammonia caramel | moderate | An ammonia caramel colour; EFSA set a group ADI for caramel colours and estimated that high consumers of some products can approach it. |
| E150d | Sulphite ammonia caramel | moderate | EFSA set a group ADI for caramel colors; the 4-MEI byproduct is monitored and intake by high consumers can approach the ADI. |
| E153 | Vegetable carbon | low | A black colour made from charred plant material; EFSA found reported food uses to be of no safety concern. |
| E160a | Carotenes | low | Plant-derived orange pigments (provitamin A); EFSA found reported food uses of mixed carotenes to be of no safety concern. |
| E160b | Annatto extracts | low | Seed-derived color; EFSA set updated ADIs in 2016 and exposure estimates stay within them. |
| E160c | Paprika extract | low | Pepper-derived color; EFSA found no safety concern at reported use levels. |
| E160e | Beta-apo-8'-carotenal | low | An orange carotenoid colour; EFSA set an ADI and estimated dietary exposure stays within it. |
| E162 | Beetroot red (betanin) | low | A red colour from beetroot; EFSA found no safety concern and placed no numeric intake limit on it. |
| E163 | Anthocyanins | low | Purple-red plant colours from fruit and vegetables; EFSA found reported food uses to be of no safety concern. |
| E170 | Calcium carbonate | low | A mineral (chalk) also used as a calcium source; EFSA found no safety concern at reported uses. |
| E171 | Titanium dioxide | higher | EFSA concluded in 2021 that genotoxicity could not be ruled out and the EU withdrew its food authorization in 2022; it remains permitted in some other jurisdictions, including the US. |
| E172 | Iron oxides and hydroxides | low | Mineral iron-based colours; EFSA set an ADI and estimated dietary exposure stays within it. |
| E200 | Sorbic acid | low | A common preservative; EFSA set a revised group ADI for sorbic acid and sorbates in 2019 and typical exposure stays within it. |
| E202 | Potassium sorbate | low | Common preservative; EFSA set a revised group ADI in 2019 and typical exposure stays within it. |
| E203 | Calcium sorbate | low | A preservative in the sorbate group; EFSA set a revised group ADI in 2019 that typical exposure stays within. |
| E210 | Benzoic acid | moderate | A preservative with an EFSA group ADI; intake by children who consume many soft drinks can approach the ADI. |
| E211 | Sodium benzoate | moderate | Preservative with an EFSA group ADI; intake by children who consume many soft drinks can approach the ADI, and benzene can form in some drinks that also contain vitamin C. |
| E212 | Potassium benzoate | moderate | A preservative in the benzoate group with an EFSA group ADI; intake by high consumers of soft drinks can approach the ADI. |
| E220 | Sulphur dioxide | moderate | EFSA's 2022 re-evaluation could not confirm the safety of the previous ADI due to data gaps, and some people are sensitive to sulphites; it must be declared as an allergen in the EU and US. |
| E223 | Sodium metabisulphite | moderate | A sulphite preservative and antioxidant; EFSA's 2022 re-evaluation could not confirm the previous ADI due to data gaps, and it must be declared as an allergen in the EU and US. |
| E224 | Potassium metabisulphite | moderate | A sulphite preservative and antioxidant; EFSA's 2022 re-evaluation could not confirm the previous ADI due to data gaps, and it must be declared as an allergen in the EU and US. |
| E234 | Nisin | low | A preservative produced by fermentation; EFSA re-evaluated it and set an ADI that estimated exposure stays within. |
| E235 | Natamycin | low | A preservative used on the surface of cheese and cured meats; EFSA set an ADI that estimated exposure stays within. |
| E249 | Potassium nitrite | higher | Curing salt for processed meats; EFSA's 2023 assessment found dietary exposure to nitrosamines, which can form from nitrites, raises a health concern across age groups. |
| E250 | Sodium nitrite | higher | Curing salt for processed meats; EFSA's 2023 assessment found dietary exposure to nitrosamines, which can form from nitrites, raises a health concern, and the EU tightened permitted levels in 2023. |
| E251 | Sodium nitrate | moderate | Can convert to nitrite in the body; EFSA re-confirmed the ADI in 2017 but the EU lowered permitted use levels in 2023 as a precaution around nitrosamine formation. |
| E260 | Acetic acid | low | The acid in vinegar; regulators place no numeric intake limit on it. |
| E262 | Sodium acetates | low | Salts of acetic acid used to regulate acidity; regulators place no numeric intake limit on them. |
| E263 | Calcium acetate | low | A salt of acetic acid used to regulate acidity; regulators place no numeric intake limit on it. |
| E270 | Lactic acid | low | Naturally produced in fermentation; regulators place no numeric intake limit on it. |
| E280 | Propionic acid | low | A preservative that slows mould in baked goods; EFSA found no safety concern and placed no numeric intake limit on it. |
| E282 | Calcium propionate | low | A preservative that slows mould in bread and baked goods; EFSA found no safety concern at reported uses. |
| E290 | Carbon dioxide | low | A packaging and carbonation gas; regulators place no numeric intake limit on it. |
| E296 | Malic acid | low | Fruit acid found naturally in apples; regulators place no numeric intake limit on it. |
| E300 | Ascorbic acid (vitamin C) | low | Vitamin C used as an antioxidant; EFSA found no safety concern and no need for a numeric ADI. |
| E301 | Sodium ascorbate | low | A form of vitamin C used as an antioxidant; EFSA found no safety concern and no need for a numeric ADI. |
| E304 | Ascorbyl palmitate | low | A fat-soluble form of vitamin C used as an antioxidant; EFSA found no safety concern at reported uses. |
| E306 | Tocopherol-rich extract (vitamin E) | low | Vitamin E used as an antioxidant; EFSA found no safety concern at reported uses. |
| E307 | Alpha-tocopherol | low | A form of vitamin E used as an antioxidant; EFSA found no safety concern at reported uses. |
| E310 | Propyl gallate | moderate | A synthetic antioxidant with an EFSA group ADI for gallates; some consumers can approach the group limit. |
| E320 | Butylated hydroxyanisole (BHA) | moderate | Synthetic antioxidant with an EFSA ADI; IARC classifies it as Group 2B (possibly carcinogenic, based on high-dose animal data) while typical dietary exposure stays below the ADI. |
| E321 | Butylated hydroxytoluene (BHT) | moderate | Synthetic antioxidant; EFSA set an ADI in 2012 and high consumers can approach it. |
| E322 | Lecithins | low | Emulsifier usually from soy or sunflower; EFSA found no safety concern at reported uses. |
| E325 | Sodium lactate | low | A salt of lactic acid used to regulate acidity and hold moisture; regulators place no numeric intake limit on it. |
| E327 | Calcium lactate | low | A salt of lactic acid used to regulate acidity and firm texture; regulators place no numeric intake limit on it. |
| E330 | Citric acid | low | Fruit acid found naturally in citrus; regulators place no numeric intake limit on it. |
| E331 | Sodium citrates | low | Salts of citric acid used to regulate acidity; regulators place no numeric intake limit on them. |
| E332 | Potassium citrates | low | Salts of citric acid used to regulate acidity; regulators place no numeric intake limit on them. |
| E333 | Calcium citrates | low | Salts of citric acid used to regulate acidity and firm texture; regulators place no numeric intake limit on them. |
| E334 | Tartaric acid | low | A fruit acid found naturally in grapes; JECFA set an ADI that typical use stays within. |
| E336 | Potassium tartrates (cream of tartar) | low | A salt of tartaric acid (cream of tartar) used to regulate acidity; JECFA set an ADI that typical use stays within. |
| E338 | Phosphoric acid | moderate | EFSA set a group intake limit for phosphates in 2019 and estimated that high consumers, especially children and teens, can exceed it. |
| E339 | Sodium phosphates | moderate | Part of the phosphate group for which EFSA set a group intake limit in 2019; high consumers can exceed it. |
| E340 | Potassium phosphates | moderate | Part of the phosphate group for which EFSA set a group intake limit in 2019; high consumers can exceed it. |
| E341 | Calcium phosphates | moderate | Part of the phosphate group for which EFSA set a group intake limit in 2019; also used as a raising agent and calcium source, and high consumers can exceed the group limit. |
| E392 | Extracts of rosemary | low | A plant-derived antioxidant; EFSA set an ADI that estimated exposure stays within. |
| E400 | Alginic acid | low | A seaweed-derived thickener and stabiliser; EFSA re-evaluated the alginates and found no safety concern at reported uses. |
| E401 | Sodium alginate | low | A seaweed-derived thickener and stabiliser; EFSA found no safety concern at reported uses. |
| E406 | Agar | low | Seaweed-derived gelling agent; EFSA found no safety concern at reported uses. |
| E407 | Carrageenan | moderate | Seaweed-derived thickener; EFSA kept a temporary ADI in 2018 because of data gaps and asked for further studies. |
| E410 | Locust bean gum | low | Carob-seed thickener; EFSA found no safety concern for the general population at reported uses. |
| E412 | Guar gum | low | Plant-seed thickener; EFSA found no safety concern at reported uses. |
| E414 | Gum arabic (acacia gum) | low | A plant gum (acacia) used as a thickener and stabiliser; regulators place no numeric intake limit on it. |
| E415 | Xanthan gum | low | Fermentation-derived thickener; EFSA found no safety concern at reported uses. |
| E418 | Gellan gum | low | A fermentation-derived gelling agent and thickener; EFSA found no safety concern at reported uses. |
| E420 | Sorbitol | low | A sugar alcohol (polyol) used as a sweetener and humectant; regulators set no numeric ADI, and EU labels note that eating a lot may have a laxative effect. |
| E421 | Mannitol | low | A sugar alcohol (polyol) used as a sweetener and anti-caking agent; regulators set no numeric ADI, and EU labels note that eating a lot may have a laxative effect. |
| E422 | Glycerol | low | Humectant naturally present in fats; EFSA found no safety concern at reported uses. |
| E425 | Konjac | low | A plant-fibre thickener and gelling agent; EFSA found no safety concern in foods, though it is restricted in jelly mini-cups because of a choking risk. |
| E433 | Polysorbate 80 | moderate | Emulsifier with an EFSA group ADI; EFSA noted data gaps at re-evaluation and research on emulsifier effects on the gut is ongoing. |
| E440 | Pectins | low | Fruit-derived gelling agent; EFSA found no safety concern and no need for a numeric ADI. |
| E450 | Diphosphates | moderate | Part of the phosphate group for which EFSA set a group intake limit in 2019; high consumers can exceed it. |
| E451 | Triphosphates | moderate | Part of the phosphate group for which EFSA set a group intake limit in 2019; high consumers can exceed it. |
| E452 | Polyphosphates | moderate | Part of the phosphate group for which EFSA set a group intake limit in 2019; high consumers can exceed it. |
| E460 | Cellulose | low | Purified plant fibre (microcrystalline or powdered cellulose) used as a bulking agent and stabiliser; EFSA found no safety concern at reported uses. |
| E461 | Methyl cellulose | low | A plant-fibre-derived thickener and stabiliser; EFSA found no safety concern at reported uses. |
| E464 | Hydroxypropyl methyl cellulose | low | A plant-fibre-derived thickener and stabiliser; EFSA found no safety concern at reported uses. |
| E466 | Carboxymethylcellulose (cellulose gum) | moderate | EFSA found no safety concern at re-evaluation but noted data gaps, and research on emulsifier effects on the gut microbiome is ongoing. |
| E471 | Mono- and diglycerides of fatty acids | low | Emulsifiers digested like ordinary dietary fats; EFSA found no safety concern at reported uses. |
| E472e | Mono- and diacetyltartaric acid esters of mono- and diglycerides (DATEM) | low | An emulsifier made from mono- and diglycerides; EFSA found no safety concern at reported uses. |
| E473 | Sucrose esters of fatty acids | low | An emulsifier; EFSA set an ADI that estimated exposure stays within. |
| E475 | Polyglycerol esters of fatty acids | low | An emulsifier; EFSA found no safety concern at reported uses. |
| E476 | Polyglycerol polyricinoleate (PGPR) | low | An emulsifier used to improve the flow of chocolate; EFSA set an ADI that typical use stays within. |
| E481 | Sodium stearoyl-2-lactylate | low | An emulsifier and dough conditioner; EFSA set an ADI that estimated exposure stays within. |
| E491 | Sorbitan monostearate | low | An emulsifier; EFSA set a group ADI for sorbitan esters that estimated exposure stays within. |
| E500 | Sodium carbonates (baking soda) | low | Common raising agent; regulators place no numeric intake limit on it. |
| E551 | Silicon dioxide | moderate | An anti-caking agent; EFSA's 2018 re-evaluation could not fully conclude on safety because of data gaps and asked for more information, while current uses stay under review. |
| E575 | Glucono-delta-lactone | low | A mild acid used as an acidity regulator; regulators place no numeric intake limit on it. |
| E620 | Glutamic acid | moderate | EFSA set a group ADI for glutamates in 2017 and estimated some population groups can exceed it; glutamate is otherwise a normal component of protein-rich foods. |
| E621 | Monosodium glutamate (MSG) | moderate | EFSA set a group ADI for glutamates in 2017 and estimated that some population groups can exceed it; glutamate is otherwise a normal component of protein-rich foods. |
| E627 | Disodium guanylate | low | A flavour enhancer usually paired with glutamates; EFSA found no safety concern at reported uses. |
| E631 | Disodium inosinate | low | A flavour enhancer usually paired with glutamates; EFSA found no safety concern at reported uses. |
| E635 | Disodium 5'-ribonucleotides | low | A flavour enhancer (a blend of guanylate and inosinate); EFSA found no safety concern at reported uses. |
| E901 | Beeswax | low | A natural wax used as a glazing agent to coat confectionery and fruit; EFSA found no safety concern at reported uses. |
| E903 | Carnauba wax | low | A plant wax used as a glazing agent; EFSA set an ADI that estimated exposure stays within. |
| E904 | Shellac | low | A resin used as a glazing agent to coat confectionery and fruit; EFSA found no safety concern at reported uses. |
| E924 | Potassium bromate | higher | Flour treatment agent withdrawn from food use in the EU, UK, and Canada; IARC classifies it as Group 2B based on animal studies, and it remains permitted with limits in some jurisdictions. |
| E941 | Nitrogen | low | An inert packaging gas used to displace oxygen; regulators place no numeric intake limit on it. |
| E950 | Acesulfame K | moderate | Sweetener with an EFSA ADI that typical intakes stay within; the WHO's 2023 guideline advises against relying on non-sugar sweeteners for weight management. |
| E951 | Aspartame | moderate | EFSA and JECFA maintain an ADI that typical intakes stay well within; IARC classified it Group 2B (limited evidence) in 2023, which JECFA reviewed without changing the ADI. |
| E953 | Isomalt | low | A sugar alcohol (polyol) sweetener; regulators set no numeric ADI, and EU labels note that eating a lot may have a laxative effect. |
| E955 | Sucralose | moderate | Sweetener with a JECFA/EFSA ADI that typical intakes stay within; the WHO's 2023 guideline advises against relying on non-sugar sweeteners for weight management and EFSA re-evaluation is ongoing. |
| E960 | Steviol glycosides (stevia) | low | A plant-derived (stevia) sweetener; EFSA and JECFA set an ADI that typical intakes stay within. |
| E965 | Maltitol | low | A sugar alcohol (polyol) sweetener; regulators set no numeric ADI, and EU labels note that eating a lot may have a laxative effect. |
| E966 | Lactitol | low | A sugar alcohol (polyol) sweetener; regulators set no numeric ADI, and EU labels note that eating a lot may have a laxative effect. |
| E967 | Xylitol | low | A sugar alcohol (polyol) sweetener; regulators set no numeric ADI for people, and EU labels note that eating a lot may have a laxative effect. |
| E968 | Erythritol | low | A sugar alcohol (polyol) sweetener that is largely not metabolised; EFSA set no numeric ADI and food authorities consider approved uses acceptable, with research on other effects ongoing. |

## 50-product calibration set

The reference set the engine is tuned against: each product's inputs and the
**expected** sub-scores + final score + band. Please mark **Agree? (Y/N)** and add a
comment where you disagree.

| # | Product | Category | NOVA | Nutri | Additive tiers | Proc. | Nutr. | Add. | Score | Band | Notes | Agree? (Y/N) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Extra-virgin olive oil | Oil | 1 | C | — | 100 | 50 | 100 | **83** | high | Whole-food fat; Nutri-Score dings fat, processing pristine |  |
| 2 | Fresh banana | Fruit | 1 | A | — | 100 | 90 | 100 | **97** | high | Baseline whole food |  |
| 3 | Raw almonds | Nuts | 1 | A | — | 100 | 90 | 100 | **97** | high |  |  |
| 4 | Rolled oats (plain) | Grain | 1 | A | — | 100 | 90 | 100 | **97** | high |  |  |
| 5 | White rice | Grain | 1 | A | — | 100 | 90 | 100 | **97** | high |  |  |
| 6 | Frozen peas (plain) | Vegetable | 1 | A | — | 100 | 90 | 100 | **97** | high |  |  |
| 7 | Whole milk | Dairy | 1 | B | — | 100 | 70 | 100 | **90** | high |  |  |
| 8 | Plain Greek yogurt | Dairy | 1 | A | — | 100 | 90 | 100 | **97** | high |  |  |
| 9 | Sparkling water (plain) | Beverage | 1 | A | — | 100 | 90 | 100 | **97** | high | CONTRAST to diet soda → should score high |  |
| 10 | Honey (pure) | Sweetener | 1 | D | — | 100 | 30 | 100 | **76** | high | Whole but high sugar |  |
| 11 | Pure maple syrup | Sweetener | 1 | D | — | 100 | 30 | 100 | **76** | high |  |  |
| 12 | Natural peanut butter (peanuts only) | Spread | 2 | C | — | 80 | 50 | 100 | **73** | mid |  |  |
| 13 | Butter | Dairy fat | 3 | D | — | 55 | 30 | 100 | **53** | mid | Sat fat dings nutrition |  |
| 14 | Cheddar cheese | Dairy | 3 | D | — | 55 | 30 | 100 | **53** | mid | EDGE: nutrient-dense; compare vs sugary cereal |  |
| 15 | Canned chickpeas | Legume | 3 | A | — | 55 | 90 | 100 | **74** | mid |  |  |
| 16 | Hummus | Spread | 3 | B | low | 55 | 70 | 100 | **67** | mid |  |  |
| 17 | Tofu | Protein | 3 | B | — | 55 | 70 | 100 | **67** | mid |  |  |
| 18 | Sourdough bread (artisan) | Bakery | 3 | C | — | 55 | 50 | 100 | **60** | mid |  |  |
| 19 | Salted roasted peanuts | Nuts | 3 | B | low | 55 | 70 | 100 | **67** | mid |  |  |
| 20 | Dark chocolate 85% | Confectionery | 3 | D | low | 55 | 30 | 100 | **53** | mid |  |  |
| 21 | Potato chips (plain salted) | Snack | 3 | D | — | 55 | 30 | 100 | **53** | mid |  |  |
| 22 | Ketchup | Condiment | 4 | D | low | 20 | 30 | 100 | **36** | low |  |  |
| 23 | Mustard | Condiment | 3 | B | — | 55 | 70 | 100 | **67** | mid |  |  |
| 24 | Kombucha | Beverage | 3 | B | — | 55 | 70 | 100 | **67** | mid |  |  |
| 25 | 100% orange juice | Beverage | 1 | C | — | 100 | 50 | 100 | **83** | high | Whole but sugar-heavy |  |
| 26 | Oat milk (fortified) | Beverage | 4 | B | low, low | 20 | 70 | 100 | **50** | mid |  |  |
| 27 | Diet cola (sweeteners) | Beverage | 4 | C | moderate, moderate, moderate, low | 20 | 50 | 88 | **41** | low | EDGE: OK nutrition but NOVA4 + additives → should score LOW (anti-Yuka) |  |
| 28 | Regular cola | Beverage | 4 | E | low, low | 20 | 12 | 100 | **29** | low |  |  |
| 29 | Energy drink | Beverage | 4 | E | moderate, moderate, low | 20 | 12 | 91 | **28** | low |  |  |
| 30 | Sports drink | Beverage | 4 | D | moderate, low | 20 | 30 | 94 | **35** | low |  |  |
| 31 | Multigrain Cheerios (fortified) | Cereal | 4 | B | low | 20 | 70 | 100 | **50** | mid | EDGE: compare vs Froot Loops |  |
| 32 | Froot Loops (sugary cereal) | Cereal | 4 | E | higher, moderate, moderate | 20 | 12 | 76 | **26** | low | Colours + BHT |  |
| 33 | Granola (sweetened) | Cereal | 4 | C | — | 20 | 50 | 100 | **43** | low |  |  |
| 34 | Instant ramen noodles | Meal | 4 | E | moderate, moderate, low | 20 | 12 | 91 | **28** | low |  |  |
| 35 | Canned condensed soup | Meal | 4 | D | moderate, low | 20 | 30 | 94 | **35** | low |  |  |
| 36 | Frozen pizza | Meal | 4 | D | moderate, low, low | 20 | 30 | 94 | **35** | low |  |  |
| 37 | Milk chocolate bar | Confectionery | 4 | E | low | 20 | 12 | 100 | **29** | low | Emulsifier = low concern |  |
| 38 | Flavoured fruit yogurt | Dairy | 4 | C | low, moderate | 20 | 50 | 94 | **42** | low |  |  |
| 39 | Protein bar | Snack | 4 | C | moderate, low | 20 | 50 | 94 | **42** | low |  |  |
| 40 | Doritos (flavoured chips) | Snack | 4 | D | moderate, moderate, low | 20 | 30 | 91 | **34** | low | MSG + colours |  |
| 41 | Refined crackers | Snack | 4 | C | low | 20 | 50 | 100 | **43** | low |  |  |
| 42 | White sandwich bread (industrial) | Bakery | 4 | C | low, low | 20 | 50 | 100 | **43** | low |  |  |
| 43 | Ice cream | Dessert | 4 | D | low, low | 20 | 30 | 100 | **36** | low |  |  |
| 44 | Deli ham (cured) | Meat | 4 | D | higher, moderate | 20 | 30 | 79 | **32** | low | EDGE: nitrite=higher concern but floor(30) prevents tanking |  |
| 45 | Bacon | Meat | 4 | E | higher | 20 | 12 | 85 | **27** | low | nitrite |  |
| 46 | Chicken sausages | Meat | 4 | D | moderate, low | 20 | 30 | 94 | **35** | low |  |  |
| 47 | Peanut butter w/ sugar + palm oil | Spread | 4 | C | low | 20 | 50 | 100 | **43** | low |  |  |
| 48 | Baby food fruit puree | Baby | 3 | A | — | 55 | 90 | 100 | **74** | mid |  |  |
| 49 | Margarine spread | Dairy fat | 4 | C | low, low | 20 | 50 | 100 | **43** | low |  |  |
| 50 | Canned tuna in water | Protein | 3 | A | — | 55 | 90 | 100 | **74** | mid |  |  |

*(A machine-readable copy with reviewer columns is in
`docs/reviews/SCORE_WEIGHTS_REVIEW_2026-07.csv`.)*

## Sign-off & standing instruction

Reviewer: _______________________   Date: ____________   Overall: ☐ Approve  ☐ Approve with changes  ☐ Needs discussion

Notes / requested changes:

```
(free text)
```

**STANDING INSTRUCTION (for the engineer, if the reviewer changes any weight or
additive tier):**
1. Edit `supabase/functions/_shared/scoring/weights.json` and/or
   `additives_risk.json`.
2. **Bump `SCORE_VERSION`** in `supabase/functions/_shared/scoring/engine.ts`
   (currently `1.1.0`).
3. Log the change in `MEMORY.md` (SCORING_METHODOLOGY §8).
4. The Chunk-4 **re-score cron** (`/rescore`) then auto-re-scores every cached
   product on its next run, and `product_current_scores` immediately serves the
   new score everywhere (trending / swaps / search). **No other code changes.**
