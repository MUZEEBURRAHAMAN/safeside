#!/usr/bin/env python3
"""
ScreensDesign scraper (screensdesign.com)

WHY THIS APPROACH:
screensdesign.com is a JavaScript-rendered single-page app. The page HTML you
get from a plain `requests.get()` is just an empty shell — the real content
(app listings, screens, categories) is loaded afterwards by JavaScript from a
backend API. So `requests` + BeautifulSoup alone will NOT work.

This script uses Playwright (a real headless browser). It does two things:

  1. NETWORK CAPTURE (the smart part): it listens to every response the page
     makes and saves any JSON responses to ./output/api_responses/. This
     automatically captures the site's real API data even though we don't know
     the endpoint URLs in advance. This is almost always the cleanest data.

  2. DOM EXTRACTION (fallback): after scrolling to trigger lazy-loading, it
     pulls visible cards (title, link, image) straight from the rendered page.

HOW TO USE:
  pip install playwright
  playwright install chromium
  python screensdesign_scraper.py

Then look in ./output/:
  - api_responses/*.json   <- raw API payloads (inspect these first; the data
                              you want is almost certainly in here)
  - screens.csv / screens.json  <- DOM-extracted cards (fallback)

TIP: To find the exact API fast, open the site in Chrome, press F12 ->
Network tab -> filter "Fetch/XHR" -> reload. The JSON requests you see there
are what this script captures automatically.

NOTE: Respect the site's terms of service and robots.txt, scrape gently
(the delays below are intentional), and don't hammer their servers.
"""

import json
import csv
import re
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE_URL = "https://screensdesign.com/"
OUT_DIR = Path("output")
API_DIR = OUT_DIR / "api_responses"
HEADLESS = True          # set False to watch it work in a real window
SCROLL_ROUNDS = 15       # how many times to scroll to load more content
SCROLL_PAUSE = 1.5       # seconds between scrolls (be polite)


def safe_filename(url: str, idx: int) -> str:
    name = re.sub(r"[^a-zA-Z0-9._-]", "_", url.split("?")[0])[-80:]
    return f"{idx:03d}_{name or 'response'}.json"


def main():
    OUT_DIR.mkdir(exist_ok=True)
    API_DIR.mkdir(parents=True, exist_ok=True)

    captured = []  # (url, json_data)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        context = browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0 Safari/537.36"
            )
        )
        page = context.new_page()

        # ---- 1. Capture JSON API responses automatically ----
        def on_response(response):
            try:
                ctype = response.headers.get("content-type", "")
                if "application/json" in ctype:
                    data = response.json()
                    captured.append((response.url, data))
            except Exception:
                pass  # ignore non-JSON / failed bodies

        page.on("response", on_response)

        print(f"Opening {BASE_URL} ...")
        page.goto(BASE_URL, wait_until="networkidle", timeout=60000)

        # ---- 2. Scroll to trigger lazy-loaded content ----
        print("Scrolling to load more content...")
        last_height = 0
        for i in range(SCROLL_ROUNDS):
            page.mouse.wheel(0, 4000)
            time.sleep(SCROLL_PAUSE)
            height = page.evaluate("document.body.scrollHeight")
            print(f"  scroll {i+1}/{SCROLL_ROUNDS} (height={height})")
            if height == last_height:
                break
            last_height = height

        # ---- 3. Save captured API JSON ----
        print(f"\nCaptured {len(captured)} JSON responses.")
        for idx, (url, data) in enumerate(captured):
            fname = safe_filename(url, idx)
            (API_DIR / fname).write_text(
                json.dumps(data, indent=2, ensure_ascii=False)
            )
        print(f"Saved raw API payloads -> {API_DIR}/")

        # ---- 4. DOM extraction fallback ----
        # Generic: grab every anchor that wraps an image (typical card layout).
        # Adjust the selector after inspecting the real page if needed.
        print("\nExtracting visible cards from the DOM...")
        items = page.evaluate(
            """
            () => {
              const out = [];
              document.querySelectorAll('a').forEach(a => {
                const img = a.querySelector('img');
                const text = (a.innerText || '').trim();
                if (img || text) {
                  out.push({
                    title: text.split('\\n')[0] || null,
                    href: a.href || null,
                    img: img ? (img.src || img.getAttribute('data-src')) : null,
                    alt: img ? img.alt : null,
                  });
                }
              });
              return out;
            }
            """
        )
        # de-dupe by href
        seen, rows = set(), []
        for it in items:
            key = it.get("href")
            if key and key not in seen:
                seen.add(key)
                rows.append(it)

        (OUT_DIR / "screens.json").write_text(
            json.dumps(rows, indent=2, ensure_ascii=False)
        )
        if rows:
            with open(OUT_DIR / "screens.csv", "w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=["title", "href", "img", "alt"])
                w.writeheader()
                w.writerows(rows)
        print(f"Extracted {len(rows)} DOM cards -> {OUT_DIR}/screens.csv / .json")

        browser.close()

    print("\nDone. Inspect output/api_responses/ first — that's where the "
          "structured data lives.")


if __name__ == "__main__":
    main()
