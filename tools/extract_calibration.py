#!/usr/bin/env python3
"""Extract docs/Scoring_Calibration.xlsx into JSON fixtures for the scoring-engine tests.

Outputs:
  supabase/functions/_shared/scoring/calibration.json  (50 products + expected sub-scores/score/band)
  supabase/functions/_shared/scoring/weights.json      (composite weights + NOVA/Nutri mappings + additive penalties)

Run from repo root: python3 tools/extract_calibration.py
Stdlib only (no openpyxl dependency).
"""
import zipfile, re, json, os, sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "docs", "Scoring_Calibration.xlsx")
OUT_DIR = os.path.join(ROOT, "supabase", "functions", "_shared", "scoring")

M = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def load_sheets(z):
    shared = [
        "".join(t.text or "" for t in si.iter(f"{{{M}}}t"))
        for si in ET.fromstring(z.read("xl/sharedStrings.xml"))
    ]
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = {r.get("Id"): r.get("Target") for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))}
    sheets = {}
    for s in wb.iter(f"{{{M}}}sheet"):
        sheets[s.get("name")] = "xl/" + rels[s.get(f"{{{R}}}id")].lstrip("/")
    return shared, sheets


def read_rows(z, shared, path):
    rows = []
    for row in ET.fromstring(z.read(path)).iter(f"{{{M}}}row"):
        cells = {}
        for c in row.iter(f"{{{M}}}c"):
            col = re.match(r"[A-Z]+", c.get("r")).group()
            v = c.find(f"{{{M}}}v")
            if v is None:
                t = c.find(f".//{{{M}}}t")
                val = t.text if t is not None else None
            else:
                val = shared[int(v.text)] if c.get("t") == "s" else v.text
            cells[col] = val
        rows.append(cells)
    return rows


def parse_additives(cell):
    """'2 (higher, moderate)' -> ['higher','moderate']; '0' -> []"""
    if not cell or cell.strip() == "0":
        return []
    m = re.match(r"\d+\s*\(([^)]*)\)", cell.strip())
    return [t.strip() for t in m.group(1).split(",")] if m else []


BAND_KEY = {"Lower-processed": "high", "Moderately processed": "mid", "Higher-processed": "low"}


def main():
    z = zipfile.ZipFile(XLSX)
    shared, sheets = load_sheets(z)

    # --- Weights sheet ---
    w = {r.get("A"): r.get("B") for r in read_rows(z, shared, sheets["Weights"]) if r.get("A")}
    weights = {
        "composite": {
            "processing": float(w["Processing weight"]),
            "nutrition": float(w["Nutrition weight"]),
            "additives": float(w["Additives weight"]),
        },
        "novaToProcessing": {
            "1": float(w["NOVA 1 (unprocessed)"]),
            "2": float(w["NOVA 2 (culinary ingredient)"]),
            "3": float(w["NOVA 3 (processed)"]),
            "4": float(w["NOVA 4 (ultra-processed)"]),
        },
        "nutriToNutrition": {
            "a": float(w["Nutri A"]),
            "b": float(w["Nutri B"]),
            "c": float(w["Nutri C"]),
            "d": float(w["Nutri D"]),
            "e": float(w["Nutri E"]),
        },
        "additivePenalties": {
            "low": {"first": 0, "additional": 0},
            "moderate": {"first": 6, "additional": 3},
            "higher": {"first": 15, "additional": 8},
        },
        "additiveFloor": float(w["Floor (min additive sub-score)"]),
    }

    # --- Calibration sheet ---
    rows = read_rows(z, shared, sheets["Calibration"])
    products = []
    for r in rows[1:]:
        if not r.get("A"):
            continue
        band = r.get("K")
        products.append({
            "id": int(r["A"]),
            "product": r.get("B"),
            "category": r.get("C"),
            "input": {
                "nova": int(r["D"]) if r.get("D") else None,
                "nutriscore": (r.get("E") or "").lower() or None,
                "additiveTiers": parse_additives(r.get("F")),
            },
            "expected": {
                "processing": float(r["G"]),
                "nutrition": float(r["H"]),
                "additives": float(r["I"]),
                "score": float(r["J"]),
                "band": BAND_KEY.get(band, "unknown"),
                "bandLabel": band,
            },
            "notes": r.get("M"),
        })

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "weights.json"), "w") as f:
        json.dump(weights, f, indent=2)
        f.write("\n")
    with open(os.path.join(OUT_DIR, "calibration.json"), "w") as f:
        json.dump(products, f, indent=2)
        f.write("\n")
    print(f"Wrote {len(products)} calibration products + weights to {OUT_DIR}")
    if len(products) != 50:
        sys.exit(f"ERROR: expected 50 products, got {len(products)}")


if __name__ == "__main__":
    main()
