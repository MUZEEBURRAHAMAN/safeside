#!/usr/bin/env python3
"""
Live Open Food Facts fetch → scoring calibration (run locally).

WHY THIS IS A SEPARATE, RUN-IT-YOURSELF SCRIPT:
The calibration workbook was seeded with *representative* values for well-known
products. To finalise the scoring weights you want *real* Open Food Facts data.
This script pulls it live and applies the same v1 scoring engine, so you can
compare real scores and tune weights on real inputs.

USAGE:
  1) Put barcodes (one per line) in a text file, e.g. barcodes.txt
  2) python tools/off_live.py barcodes.txt out.csv
  3) Open out.csv; feed the columns into Scoring_Calibration.xlsx (or extend this
     script to write xlsx with openpyxl).

NOTE: set a descriptive User-Agent — Open Food Facts requires it. Be gentle
(the delay below is intentional). OFF data is ODbL: attribute the source.
"""
import sys, csv, json, time, urllib.request, urllib.parse

OFF_UA = "AIFoodScanner/0.1 (calibration; contact: you@example.com)"  # <-- set your contact
FIELDS = "product_name,brands,nova_group,nutriscore_grade,additives_tags,nutriments"

# --- v1 scoring engine (mirror of docs/SCORING_METHODOLOGY.md) ---
NOVA_MAP = {1: 100, 2: 80, 3: 55, 4: 20}
NUTRI_MAP = {"a": 90, "b": 70, "c": 50, "d": 30, "e": 12}

# starter additive risk tiers (extend from your SCORING_METHODOLOGY additives table).
# key = e-number (lowercase, no 'en:' prefix). Default tier for unknown additives = "low".
ADDITIVE_TIER = {
    "e621": "moderate", "e951": "moderate", "e950": "moderate", "e952": "moderate",
    "e211": "moderate", "e202": "moderate", "e150d": "low", "e330": "low",
    "e322": "low", "e415": "low", "e412": "low",
    "e250": "higher", "e249": "higher", "e251": "higher", "e252": "higher",  # nitrites/nitrates
    "e102": "higher", "e110": "higher", "e129": "higher", "e320": "higher", "e321": "higher",  # some colours/BHA/BHT
}

def additive_subscore(tiers):
    score = 100
    seen = {"moderate": 0, "higher": 0, "low": 0}
    for t in tiers:
        seen[t] = seen.get(t, 0) + 1
        if t == "moderate":
            score -= 6 if seen[t] == 1 else 3
        elif t == "higher":
            score -= 15 if seen[t] == 1 else 8
    return max(30, score)

def score_product(nova, nutri, additive_tags, weights=(0.50, 0.35, 0.15)):
    proc = NOVA_MAP.get(nova)
    nutr = NUTRI_MAP.get((nutri or "").lower())
    tiers = [ADDITIVE_TIER.get(a.replace("en:", "").lower(), "low") for a in (additive_tags or [])]
    add = additive_subscore(tiers)
    confidence = "high" if (proc is not None and nutr is not None) else "limited"
    proc = proc if proc is not None else 55   # fallback if NOVA missing (limited confidence)
    nutr = nutr if nutr is not None else 50
    wp, wn, wa = weights
    final = round(wp * proc + wn * nutr + wa * add)
    band = ("Lower-processed" if final >= 75 else
            "Moderately processed" if final >= 45 else "Higher-processed")
    return dict(proc=proc, nutr=nutr, add=add, score=final, band=band,
                confidence=confidence, n_additives=len(tiers))

def fetch_off(barcode):
    url = f"https://world.openfoodfacts.org/api/v2/product/{urllib.parse.quote(barcode)}.json?fields={FIELDS}"
    req = urllib.request.Request(url, headers={"User-Agent": OFF_UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    if data.get("status") != 1 and "product" not in data:
        return None
    return data.get("product", {})

def main():
    if len(sys.argv) < 3:
        print("usage: python off_live.py barcodes.txt out.csv"); sys.exit(1)
    barcodes = [l.strip() for l in open(sys.argv[1]) if l.strip()]
    with open(sys.argv[2], "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["barcode", "name", "brand", "nova", "nutriscore", "n_additives",
                    "proc_sub", "nutr_sub", "add_sub", "SCORE", "band", "confidence"])
        for bc in barcodes:
            try:
                p = fetch_off(bc)
                if not p:
                    w.writerow([bc, "NOT FOUND", "", "", "", "", "", "", "", "", "", ""]); continue
                nova = p.get("nova_group")
                nova = int(nova) if nova is not None else None
                s = score_product(nova, p.get("nutriscore_grade"), p.get("additives_tags"))
                w.writerow([bc, p.get("product_name", ""), p.get("brands", ""), nova,
                            (p.get("nutriscore_grade") or "").upper(), s["n_additives"],
                            s["proc"], s["nutr"], s["add"], s["score"], s["band"], s["confidence"]])
                print(f"{bc}  {s['score']:>3}  {s['band']:<20} {p.get('product_name','')}")
            except Exception as e:
                w.writerow([bc, f"ERROR: {e}", "", "", "", "", "", "", "", "", "", ""])
            time.sleep(0.7)  # be gentle to OFF

if __name__ == "__main__":
    main()
