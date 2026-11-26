#!/usr/bin/env python3
"""Probe one anti-bot engine against one URL. Prints a single JSON line.

Engines: playwright, patchright, nodriver, zendriver, camoufox, curl.
Needs the engines installed (this machine: ~/venvs/antibot).
    ~/venvs/antibot/bin/python engine_probe.py --engine zendriver \
        --url https://nowsecure.nl/ [--headful]
Headful needs a display: prefix with xvfb-run -a.
"""
import argparse, json, re, sys, time

def judge(url, rgb, html, status, extra=None):
    low = html.lower()
    out = {"ok": False, "detail": "", "status": status}
    if "sannysoft" in url:
        if isinstance(extra, dict): extra = extra.get("value") or []
        rows = []
        for r in (extra or []):
            if isinstance(r, str): rows.append(r)
            elif isinstance(r, dict) and isinstance(r.get("value"), str): rows.append(r["value"])
        fails = [r for r in rows if "(failed)" in r.lower() or "warning" in r.lower()]
        out["detail"] = f"rows={len(rows)} fails={len(fails)}"
        out["ok"] = len(rows) > 20 and len(fails) == 0
        if fails:
            out["fails"] = [f[:70] for f in fails[:6]]
    elif "browserleaks" in url:
        try:
            data = json.loads(html)
            out["ja4"] = data.get("ja4") or data.get("ja3_hash")
            out["detail"] = f"ja4={out['ja4']}"
            out["ok"] = bool(out["ja4"])
        except Exception:
            out["detail"] = "not json"
    elif "nowsecure" in url:
        blocked = any(s in low for s in ["just a moment", "challenge-platform", "cf-chl", "verify you are human", "enable javascript and cookies"])
        out["detail"] = "cloudflare-block" if blocked else ("ok" if status == 200 else f"http {status}")
        out["ok"] = status == 200 and not blocked
    elif "reddit" in url:
        blocked = any(s in low for s in ["whoa there", "blocked by network security", "unusual traffic", "access denied"])
        posts = html.count("shreddit-post")
        out["detail"] = ("blocked" if blocked else f"len={len(html)} posts={posts}")
        out["ok"] = status == 200 and not blocked and posts > 3
    else:
        out["detail"] = f"len={len(html)}"
        out["ok"] = status == 200 and len(html) > 500
    return out

def run_playwright(url, headless, patch=False):
    if patch:
        from patchright.sync_api import sync_playwright
    else:
        from playwright.sync_api import sync_playwright
    UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
          "Chrome/145.0.0.0 Safari/537.36")
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=headless,
                                    args=["--disable-blink-features=AutomationControlled", "--no-sandbox"])
        ctx = browser.new_context(user_agent=UA, viewport={"width": 1280, "height": 900}, locale="en-US")
        ctx.add_init_script("Object.defineProperty(navigator,'webdriver',{get:()=>undefined})")
        page = ctx.new_page()
        resp = page.goto(url, wait_until="domcontentloaded", timeout=45000)
        page.wait_for_timeout(7000)
        html = page.content()
        status = resp.status if resp else 0
        rows = page.evaluate("Array.from(document.querySelectorAll('tr')).map(e=>e.innerText.replace(/\\n/g,' | '))")
        browser.close()
    return html, status, rows

def run_nodriver(url, headless):
    import asyncio, tempfile, nodriver as uc
    async def go():
        browser = await uc.start(headless=headless, user_data_dir=tempfile.mkdtemp(), browser_args=["--no-sandbox"])
        try:
            tab = await browser.get(url)
            await tab.sleep(9)
            html = await tab.get_content()
            rows = await tab.evaluate("Array.from(document.querySelectorAll('tr')).map(e=>e.innerText.replace(/\\n/g,' | '))")
            return html, rows
        finally:
            try: browser.stop()
            except Exception: pass
    html, rows = asyncio.run(go())
    return html, 200, rows

def run_zendriver(url, headless):
    import asyncio, tempfile, zendriver as zd
    async def go():
        browser = await zd.start(headless=headless, user_data_dir=tempfile.mkdtemp(), browser_args=["--no-sandbox"])
        try:
            tab = await browser.get(url)
            await tab.sleep(9)
            html = await tab.get_content()
            rows = await tab.evaluate("Array.from(document.querySelectorAll('tr')).map(e=>e.innerText.replace(/\\n/g,' | '))")
            return html, rows
        finally:
            try: browser.stop()
            except Exception: pass
    html, rows = asyncio.run(go())
    return html, 200, rows

def run_camoufox(url, headless):
    from camoufox.sync_api import Camoufox
    with Camoufox(headless=headless, geoip=False, humanize=True) as browser:
        page = browser.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=45000)
        page.wait_for_timeout(9000)
        html = page.content()
        rows = page.evaluate("Array.from(document.querySelectorAll('tr')).map(e=>e.innerText.replace(/\\n/g,' | '))")
    return html, 200, rows

def run_curl(url):
    from curl_cffi import requests
    r = requests.get(url, impersonate="chrome", timeout=30)
    return r.text, r.status_code, []

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--headful", action="store_true")
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    t0 = time.time()
    try:
        if a.engine == "curl":
            html, status, rows = run_curl(a.url)
        elif a.engine == "playwright":
            html, status, rows = run_playwright(a.url, not a.headful)
        elif a.engine == "patchright":
            html, status, rows = run_playwright(a.url, not a.headful, patch=True)
        elif a.engine == "nodriver":
            html, status, rows = run_nodriver(a.url, not a.headful)
        elif a.engine == "zendriver":
            html, status, rows = run_zendriver(a.url, not a.headful)
        elif a.engine == "camoufox":
            html, status, rows = run_camoufox(a.url, not a.headful)
        else:
            raise SystemExit(f"unknown engine {a.engine}")
        res = judge(a.url, None, html, status, rows)
        res.update(engine=a.engine, mode="headful" if a.headful else "headless", url=a.url,
                   seconds=round(time.time() - t0, 1), label=a.label)
    except Exception as e:
        res = {"engine": a.engine, "mode": "headful" if a.headful else "headless", "url": a.url,
               "ok": False, "detail": f"{type(e).__name__}: {str(e)[:180]}",
               "seconds": round(time.time() - t0, 1), "label": a.label}
    print(json.dumps(res, ensure_ascii=False))

if __name__ == "__main__":
    main()
