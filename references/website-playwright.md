# Wrapping a website (headless browser) into a CLI

Use when the data only exists as rendered DOM: JS-heavy SPAs, bot-walled
pages, anything where view-source is an empty `<div id="root">`.

## Decision ladder (cheapest first — never open a browser before proving you need one)

1. `curl` the page — is the data already in the HTML? (view-source check)
2. Hidden endpoints — devtools Network: SPAs almost always fetch JSON. Wrap
   THAT (see api-http.md).
3. Feeds (`*.rss`, `sitemap.xml`) and oEmbed — often the sanctioned surface.
4. Only then: headless browser. A browser engine costs ~2-10s/page + memory
   and is the first thing a site breaks when it wants to.

## The playwright wrapper skeleton

Python + playwright (installed on this machine for python3; browsers may need
`playwright install chromium` or system Chrome via `channel="chrome"`):

```python
from playwright.sync_api import sync_playwright

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome 129.0.0.0 Safari/537.36"

def render(url, wait_for="shreddit-post", timeout=30000):
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True,
            args=["--disable-blink-features=AutomationControlled"])
        ctx = browser.new_context(user_agent=UA, viewport={"width":1280,"height":900},
                                  locale="en-US")
        ctx.add_init_script("Object.defineProperty(navigator,'webdriver',{get:()=>undefined})")
        page = ctx.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=timeout)
        page.wait_for_selector(wait_for, timeout=timeout)   # data-anchored wait
        html = page.content()
        browser.close()
        return html
```

Then parse with your stdlib HTML parser — keep extraction pure so it can be
unit-tested against saved HTML fixtures.

## Extraction rules

- Wait for a **data-bearing selector**, never `networkidle` blindly and never
  fixed sleeps longer than ~2s (slow, flaky both ways).
- Prefer attributes on custom elements (`<shreddit-post score="230">`) over
  pixel/DOM-position scraping; attributes are contracts, layout is not.
- Scroll for pagination only if the site has no "next" link or API page
  param; scrolling is the most fragile pattern there is.
- Save one real page per site as `fixtures/<page>.html` inside the skill for
  testing the parser offline.

## Stealth & blocks — what actually works (2026 field notes)

Honest ordering, most→least effective:

1. **A different data path.** If a site blocks browsers, RSS/undocumented
   API/mirrors usually still work (reddit: RSS + archive API while the SPA
   shows a JS-challenge block page). Changing engines beats beating checks.
2. **Headful real Chrome** (`channel="chrome", headless=False`) — passes most
   fingerprinting that kills headless. On macOS it steals focus; on Linux use
   `xvfb-run`. Slower, annoying, but reliable.
3. **Real profile with cookies** — for sources the USER has an account on,
   borrow their logged-in browser (see the aside-browser / browseros skills
   in this environment). Respects no-anonymous constraints but uses the
   user's own session.
4. Scrubbed headless (`navigator.webdriver` removed, real UA+viewport,
   `--disable-blink-features=AutomationControlled`) — passes naive checks,
   fails serious ones (Cloudflare, PerimeterX, reddit's challenge).
5. Never: UA rotation loops, proxy hammering, solving challenges
   programmatically. That is an arms race you lose and a ToS violation.

Detect a block by content, not status: 200 + "unusual traffic", "blocked",
"Enable JavaScript", empty `<title>` — treat as blocked, switch engines.

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

- `--engine browser` explicit (HTTP engine stays default when both exist).
- `--timeout-ms`, and exit 3 on block detection with a stderr hint about
  which engine to use instead.
- Verbose mode prints the render timeline (goto → selector → count).
