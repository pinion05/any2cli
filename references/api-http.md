# Wrapping a web API into a CLI

For sources that expose HTTP endpoints — official APIs, undocumented app
backends, RSS/Atom feeds, community archives. Read this even for "website"
sources: most sites leak usable endpoints, and an HTTP engine is always
faster and cheaper than a browser engine.

## 1. Find the endpoints (in order of reliability)

1. **Official docs** — check auth model, rate limits, pagination FIRST. But
   verify every endpoint live before relying on it; docs rot.
2. **Undocumented app backends** — open the site's devtools Network tab (or
   headless browser request log), note what the SPA actually calls. These are
   usually JSON, sometimes unauthenticated for read paths.
3. **Feeds** — `.rss`/`.atom` on any path, `?format=json` variants. Feeds are
   often the last anonymous surface when an API locks down (reddit 2024+).
4. **Community archives/mirrors** — for platforms that killed anonymous API
   access, someone usually runs an archive (arctic-shift for reddit) or a
   proxy frontend (redlib). Search "<platform> api alternative site:github.com".
5. **Embed/oEmbed surfaces** — `oembed?url=` endpoints survive lockdowns and
   at minimum resolve id → title/author (no scores, but cheap).

## 2. Probe checklist (curl, before writing any code)

```bash
curl -sS -D /tmp/h -m 20 -A "<honest UA with purpose+contact>" \
     "https://host/endpoint?limit=2" | head -c 800; grep -i -E "ratelimit|retry" /tmp/h
```

- Does it work with no auth? With a descriptive UA? With a browser UA?
- Which fields come back — ids, permalinks, scores, timestamps?
- Rate-limit headers (`x-ratelimit-remaining`, `retry-after`)?
- Pagination style: `?after=` cursor, `?page=`, Link headers, `?before=`?
- Does it 403/429 instantly (IP flagged) or only under load?
- Same data from more than one source? (→ fallback engines)

Record negative results too — they decide the fallback order later.

## 3. Multi-engine fallback pattern

The heart of a durable wrapper. Requirements:

- Each engine implements the SAME normalized record shape
  (`post_from_rss`, `post_from_arctic`, ... in the reddit example).
- A command tries engines in order; on `RateLimited`/`CliError` it falls to
  the next; when it succeeds via a fallback, it logs the switch on stderr and
  marks the engine in output (`engine: arctic(title-search)`).
- Fields only an engine provides get a source marker
  (`"score_source": "arctic-archive"`) so stale-vs-live is always visible.
- Order engines by (freshness × cheapness): live-feed first, archive second,
  heavy-scrape last.

```python
try:
    items = self.rss(path, params)          # fresh, but rate-limited
except RateLimited:
    log("rss rate-limited; falling back to arctic-shift")
    items = self.arctic("/posts/search", {...})   # archive, always there
```

## 4. Be a good citizen (this is what keeps the CLI alive)

- Descriptive User-Agent: `toolname/version (purpose; contact)`. Rotating
  browser UAs to evade limits gets the whole IP blocked — don't.
- Min-interval per host (default 5s anonymous), disk-persisted so
  back-to-back CLI runs also throttle. Jitter ±10%.
- Cache with TTL; immutable lookups (by id) can cache 24h.
- On 429: honor Retry-After, clamp to 60s, retry ≤3, then switch engines
  and exit 3 if nothing works. Never tight-loop a 403 — it means "go away".
- Keep request count per command O(1)+1: one listing call + one batched
  enrichment call (ids joined, one request per 100).

## 5. Normalization rules

- Epoch timestamps in records + human string in table views.
- Always emit: stable id, permalink/absolute url, source marker.
- Missing ≠ null-spam: omit or `·`. Keep JSON records stable over time —
  scripts depend on field names more than values.
- Fullnames vs bare ids (`t3_1wi6dpv` vs `1wi6dpv`): store bare, render
  fullname. Accept both on input, plus URLs.

## 6. When there is no API at all

If the site only renders HTML with the data baked in (no XHR to JSON, no
feeds), go to [website-playwright.md](website-playwright.md). If the HTML is
static (view-source contains the data), plain curl + an HTML parser is still
an "API engine" — cheaper than a browser; try it first.
