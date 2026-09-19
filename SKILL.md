---
name: any2cli
description: Use when the user wants anything turned into a CLI — wrap a website (headless-browser), a web API, or a desktop app into shell commands; triggers on "CLI for X", "command-line wrapper", "make it a CLI", "wrap this site/API/app", "script it from the shell", building a scraper/reader CLI, or reading reddit (subreddits, posts, comments, upvotes) from the terminal.
---

# any2cli — turn anything into a CLI

Everything that exposes data — a website, an HTTP API, a desktop app — can be
driven from the shell. Build one small CLI per source, follow the same contract
every time, and both humans and agents get a predictable tool they can compose.

**Core principle: probe before you build, degrade gracefully, output JSON when
piped.** The hard part of any wrapper is never the argparse — it is discovering
which access path actually works today (official API? undocumented endpoint?
RSS? rendered DOM?) and surviving rate limits, blocks, and schema drift.

## Workflow

1. **Classify the source** (below) and read the matching reference.
2. **Probe live before writing code.** curl the endpoints / load the page in a
   headless browser / AppleScript the app — confirm which data is reachable
   anonymously and what the real limits are. Never trust docs or memory over a
   live probe; endpoints rot (see the reddit example: the documented `.json`
   API 403s logged-out while undocumented RSS works fine).
3. **Design the command surface** nouns-as-subcommands, one resource per
   subcommand (see the contract below).
4. **Implement single-file, stdlib-only if possible.** One executable script,
   no venv, no build step. Dependencies are a failure mode.
5. **Multi-engine fallback.** Assume your primary engine will be rate-limited
   or blocked someday; wire a second source of the same data behind the same
   subcommand and switch on failure (log the switch on stderr).
6. **Verify every subcommand with a live run** before calling it done — table
   output for humans, `--format json` for agents, exit codes checked.
7. **Install as a symlink** in `~/.local/bin` (or document the full path) and
   write a short README with verified example invocations.

## Source routing

| Source | First probe | Reference |
|---|---|---|
| Web API (official or undocumented) | curl the endpoint with a descriptive UA; check auth, rate-limit headers, pagination | [references/api-http.md](references/api-http.md) |
| Website (HTML only, no API) | headless Playwright; check if data is in initial HTML vs JS-rendered | [references/website-playwright.md](references/website-playwright.md) |
| Desktop app | AppleScript (macOS) / CDP (Electron) / accessibility driver | [references/desktop-apps.md](references/desktop-apps.md) |

Many real sources are hybrids — reddit serves RSS + a community archive API +
JS-rendered HTML; the CLI composes all three. Read
[references/api-http.md](references/api-http.md) for the fallback-engine
pattern regardless of source type.

## The CLI contract (every wrapper follows this)

Keep it small enough to memorize; it is what makes wrappers composable:

```
tool <noun> <param> [filters] [--format table|json|jsonl|md]
                        [--limit N] [--fresh] [--cache-ttl SEC] [-v]
```

- **Output**: table when stdout is a tty, JSON when piped. `--format` overrides.
  JSON for lists wraps as `{"count": N, "engine": "...", "items": [...]}`.
- **Exit codes**: 0 ok · 2 usage · 3 rate-limited/blocked · 4 not found · 1 other.
  Agents depend on these to decide whether to retry.
- **Cache + throttle by default.** Disk cache (`~/.cache/any2cli/<tool>/`) with
  TTL; min-interval per host; honor `Retry-After`. A wrapper that hammers a
  source gets its user blocked — that is the #1 way these tools die.
- **Stderr is for humans/logs** (engine switches, warnings); stdout stays
  machine-parseable.
- **No secrets in argv.** Tokens come from env vars or a config file.
- **`--version`, `--help` with examples** in the epilog.
- **Fields**: include ids and permalinks/urls so output can feed the next
  command; include a `*_source` marker when a field comes from a fallback
  (e.g. archived vs live scores).

Full checklist: [references/cli-design.md](references/cli-design.md).

## Worked example: `reddit` (read reddit anonymously)

`examples/reddit/` — single-file Python 3 CLI (stdlib only), zero accounts,
zero API keys. The example's core artifact is **`examples/reddit/KNOWHOW.md`**:
the full trial-and-error record (every blocked path, every HTML-parsing trap,
how to re-probe when endpoints rot). Read it before wrapping any locked-down
site — it is the template for the probing process itself.

The CLI demonstrates every pattern in this skill:

- four engines, one interface, auto-fallback: optional OAuth app-only tokens
  (live scores + ratios, env opt-in) → redlib community mirror (live
  upvotes) → reddit RSS (fresh listings/search) + arctic-shift archive
  (score enrichment) — with per-host throttling, caching, Retry-After
  backoff, and engine switches logged to stderr;
- probing drove the design: the "documented" logged-out `.json` API and even
  a real headful browser are blocked — the CLI is built on what live probes
  proved works (a mirror, feeds, two archives, oembed);
- full contract compliance (formats, exit codes, ids in output, score-source
  markers for live-vs-archived values).

```bash
REDDIT=~/.agents/skills/any2cli/examples/reddit/reddit
$REDDIT posts r/python --sort top --time week --limit 10   # listing + upvotes
$REDDIT search "rust vs go" --sort top --time month        # site-wide search
$REDDIT search asyncio --sub python                        # in-subreddit search
$REDDIT subs "machine learning"                            # find subreddits
$REDDIT post 1wi6dpv                                       # one post: score/ratio
$REDDIT comments 1wi6dpv --limit 50 --sort top             # comment tree + scores
$REDDIT user spez                                          # user history
```

Usage and engine notes: [examples/reddit/README.md](examples/reddit/README.md).
Verification: `examples/reddit/smoke-test.sh` (live-runs every subcommand).

## Anti-blocking quick rules

- Send a stable, honest `User-Agent` with a contact/purpose note.
- Sleep between requests (2–10s for anonymous web endpoints); jitter it.
- Cache aggressively; anything within TTL costs no requests.
- On 429/403: back off (honor `Retry-After`), then switch engines — never
  retry-loop the same blocked path.
- Headless browsers: real UA, real viewport, `navigator.webdriver` scrubbed;
  if a JS challenge still blocks you, the IP is flagged — use a different
  engine or a mirror, don't fight the challenge.

## Worked example 2: `ncafe` (read Naver Cafe anonymously)

`examples/ncafe/` — single-file Python 3 CLI (stdlib only), zero accounts,
zero API keys. Two commands covering the two user intents:

```bash
ncafe search 캠핑 --sort date          # ARTICLES across ALL naver cafes
ncafe search 캠핑카 --where trade      # trade articles only
ncafe cafes 레트로게임                 # find CAFES by name + description
```

What it demonstrates beyond the reddit example:

- **SSR site, no browser needed**: the probe proved the page is server-rendered
  and the infinite-scroll XHR (`s.search.naver.com/p/cafe/48/...`) answers
  anonymous curl with an honest UA — the browser was used to *discover* the
  endpoint, then dropped entirely.
- **Soft rate-limit contract**: Naver returns HTTP 200 with an EMPTY body when
  throttled — detected by body length, not status code; retry → engine
  fallback (www SSR) → exit 3.
- **Pagination honestly scoped**: `start=` only pages when a browser-issued
  `nlu_query` accompanies it; the CLI documents one-page-per-invocation
  instead of faking deep pagination.

Probing record: [examples/ncafe/KNOWHOW.md](examples/ncafe/KNOWHOW.md).
Verification: `examples/ncafe/smoke-test.sh` (9/9 live, 2026-09-19).

## Worked example 3: `dc` (read DC Inside anonymously)

`examples/dc/` — Korean community portal, no accounts, no cookies, stdlib
HTTP only. The interesting part is the comment engine: comments live behind
an XHR whose form the site's `comment.js` builds — recovered by reading the
JS source, then capturing the browser's real POST body via a direct CDP
websocket (`Network.requestWillBeSent.postData`), then replaying it
sessionless. The form's `e_s_n_o` token turned out to be shared/static —
no cookie jar needed at all.

```bash
dc posts programming --page 2        # gallery list, notices stripped
dc search programming 파이썬 --field all
dc post programming 2939751          # body + nested comment tree (depth)
dc posts minor:ai                    # minor galleries (mgallery) too
```

Notable inversions documented in its KNOWHOW: mobile UA is required for
*browser* access but **blocked** on the plain-HTTP surface (honest tool UA
passes); the "combined search" is a Daum proxy and useless; mini galleries
are member-only so unsupported.

Probing record: [examples/dc/KNOWHOW.md](examples/dc/KNOWHOW.md).
Verification: `examples/dc/smoke-test.sh` (9/9 live, 2026-09-19).

## When NOT to use this skill

- A mature official CLI already exists (`gh`, `notion`, `vastai`) — use it.
- One-shot extraction (single page, once) — just curl/scrape inline, no CLI.
- The source requires actions you cannot reverse (payments, destructive ops)
  — wrap read-only first, or don't wrap at all.
