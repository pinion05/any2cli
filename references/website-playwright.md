# Wrapping a website (browser engine) into a CLI

Use when the data only exists as rendered DOM: JS-heavy SPAs, bot-walled
pages, anything where view-source is an empty `<div id="root">`.

## Decision ladder (cheapest first — never open a browser before proving you need one)

1. `curl` the page — is the data already in the HTML? (view-source check)
2. Hidden endpoints — devtools Network: SPAs almost always fetch JSON. Wrap
   THAT (see api-http.md).
3. Feeds (`*.rss`, `sitemap.xml`) and oEmbed — often the sanctioned surface.
4. **TLS-fingerprint wall, no JS needed** → `curl_cffi`, not a browser.
5. Only then: headless browser. A browser engine costs ~2-10s/page + memory
   and is the first thing a site breaks when it wants to.

## Which engine — measured, not assumed (2026-11-26, this machine)

Run `references/engine_probe.py` to reproduce. Same targets, same IP, headless,
system Chrome 145, 9s settle time.

| Engine | bot.sannysoft 58 rows | Cloudflare (nowsecure.nl) | reddit r/python | License | Verdict |
|---|---|---|---|---|---|
| **zendriver** | **0 fail** | **pass** (~30s) | **pass** | AGPL-3.0 | **default browser engine** |
| nodriver | 0 fail | pass (~30s) | pass | AGPL-3.0 | equal result, asyncio-first API |
| camoufox | 1 fail (`Chrome` row — it is Firefox) | pass (~32s) | pass | MPL-2.0 | Firefox-fingerprint targets, Google |
| patchright | 1 fail (`WebDriver present`) | **HTTP 522 (2/2 runs)** | pass | Apache-2.0 | only to reuse existing Playwright code |
| playwright | 1 fail (`WebDriver present`) | **HTTP 522 (2/2 runs)** | pass | Apache-2.0 | not for walls |
| curl_cffi | n/a (no JS) | HTTP 522 | block page (8.4 KB) | MIT | APIs and plain HTML only |

What the numbers mean:

- **Playwright leaks `navigator.webdriver` even with `add_init_script` and
  `channel="chrome"`.** The deeper tell is the CDP control plane
  (`Runtime.enable`, `Target.setAutoAttach`) — a JS-layer patch cannot reach it.
  Headful did not change the Cloudflare result (still 522), so headful is not a
  reason to keep Playwright.
- **zendriver/nodriver drive the system Chrome over a DevTools WebSocket with no
  Playwright handshake**, and pass both the fingerprint page and Cloudflare
  headless. They are the same lineage (nodriver is zendriver's origin; zendriver
  is the maintained fork).
- **camoufox** (Firefox fork) passes Cloudflare but is the slowest and fails the
  Chrome-specific row by design.
- **reddit is not a wall for any engine** — it serves the SPA to all of them.
  Do not use it as an anti-bot benchmark. `curl_cffi` does get a block page.
- **Do not read a block from the status alone**: the Cloudflare gate returned
  **200** to camoufox/zendriver while Playwright got **522**. Judge by content
  (challenge markers, empty root, missing data selector) AND status.

Licenses: nodriver/zendriver are AGPL-3.0 — fine for local/internal CLIs, but if
you ship the tool as a service, read the obligations. patchright/camoufox/curl_cffi
are permissive.

## zendriver skeleton (primary)

```python
import asyncio, tempfile, zendriver as zd

async def render(url, wait_selector=None, timeout_ms=45_000):
    browser = await zd.start(headless=True, user_data_dir=tempfile.mkdtemp())
    try:
        tab = await browser.get(url)
        if wait_selector:
            await tab.wait_for(wait_selector, timeout=timeout_ms)
        else:
            await tab.sleep(3)
        return await tab.get_content()
    finally:
        browser.stop()

html = asyncio.run(render("https://example.com/list", wait_selector="article"))
```

- `tempfile.mkdtemp()` per run: zendriver/nodriver reuse one profile by default,
  so cookies leak between unrelated targets unless you isolate them.
- Wait on a **data-bearing selector**, not a fixed 9s. The 9s in the benchmark
  above was deliberate, to give challenges time to clear.
- `browser.stop()` in `finally` — leaked Chrome processes are the usual reason a
  second run "mysteriously" fails.
- zendriver can print asyncio atexit warnings on exit; they go to stderr. Keep
  stdout JSON-only in the CLI wrapper and they are harmless.

## curl_cffi skeleton (TLS wall, no JS)

```python
from curl_cffi import requests

r = requests.get(url, impersonate="chrome", timeout=30)   # same JA4 as real Chrome
if r.status_code != 200 or "challenge" in r.text.lower():
    ...  # escalate to zendriver
```

6.4 MB wheel, MIT, no browser. For read-only JSON/HTML endpoints behind
Cloudflare's *TLS* layer this passes where stdlib `urllib` gets 403. It cannot
run a JS challenge, so keep it strictly as the HTTP rung of the ladder.

## Existing Playwright code

If the CLI already has a Playwright wrapper, switching engines is a rewrite. In
that case prefer `patchright` + **system Chrome** (`channel="chrome"`) over
vanilla: same API, fewer CDP leaks — but expect it to still fail hard walls
(522 above). Never bundle Chromium for anti-bot work; bundled builds hang on
Cloudflare sites.

## Extraction rules

- Wait for a **data-bearing selector**, never `networkidle` blindly and never
  fixed sleeps longer than ~2s (slow, flaky both ways).
- Prefer attributes on custom elements (`<shreddit-post score="230">`) over
  pixel/DOM-position scraping; attributes are contracts, layout is not.
- Scroll for pagination only if the site has no "next" link or API page
  param; scrolling is the most fragile pattern there is.
- Save one real page per site as `fixtures/<page>.html` inside the skill for
  testing the parser offline.

## Stealth & blocks — what actually works

1. **A different data path.** If a site blocks browsers, RSS/undocumented
   API/mirrors usually still work (reddit: RSS + archive API while the SPA
   shows a JS-challenge block page). Changing engines beats beating checks.
2. **zendriver headless** — passes the fingerprint page and Cloudflare in the
   test above. Try it before anything headful.
3. **camoufox** when the target expects Firefox (Google surfaces) or when the
   Chromium TLS shape is flagged by a CDN.
4. **Real profile with cookies** — for sources the USER has an account on,
   borrow their logged-in browser. Respects no-anonymous constraints but uses
   the user's own session.
5. **Headful** (`xvfb-run -a`) — measured no better than headless for
   zendriver/nodriver; keep it for sites that specifically dislike
   `HeadlessChrome` in the UA.
6. Never: UA rotation loops, proxy hammering, solving challenges
   programmatically. That is an arms race you lose and a ToS violation.

Detect a block by content, not status: 200 + "unusual traffic", "Just a
moment", "Enable JavaScript", empty `<title>`, or a missing data selector —
treat as blocked and switch engines.

## Caching & session reuse for browser engines

Browser pages are expensive; cache harder than HTTP:

- Cache rendered+parsed records under `~/.cache/any2cli/<tool>/` (TTL 10min
  for listings, 24h for detail pages).
- Keep a persistent context per host in `~/.cache/any2cli/<tool>/profile/`
  (cookies survive, some walls soften) — but never persist credentials there
  without the user knowing.
- One browser process per CLI invocation is fine at CLI scale; a daemon with
  CDP is only worth it above ~50 pages/run (agent-browser CLI in this
  environment already does this — reuse it instead of building a daemon).

## CLI shape for browser engines

Same contract as everything else, plus:

- `--engine http|browser` explicit (HTTP stays default when both exist).
- `--timeout-ms`, and exit 3 on block detection with a stderr hint about
  which engine to use instead.
- Verbose mode prints the render timeline (goto → selector → count).
