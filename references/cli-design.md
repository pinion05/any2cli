# CLI design contract — details

The contract in SKILL.md, expanded. Every any2cli wrapper follows this so that
knowing one tool means knowing all of them.

## Command surface

- Nouns as subcommands, one resource per subcommand: `posts`, `search`,
  `subs`, `post`, `comments`, `user`. Verbs are rare; reading tools list
  nouns, action tools take verbs (`notify send`, ` gist create`).
- Parameters: positional = the resource identity; flags = filters/pagination.
- Accept every common spelling of the identity. The reddit CLI's `post`
  command takes `1wi6dpv`, `t3_1wi6dpv`, or any `reddit.com/r/x/comments/...`
  URL. Parse, don't complain.
- `--limit N` everywhere (default 25, cap sensible). `--format` everywhere.

## Output

Default: `table` if `sys.stdout.isatty()` else `json`. One flag, `--format`,
choices `table|json|jsonl|md`.

- `json`: list payloads wrap as `{"count": N, "engine": "...", "items": [...]}`,
  `ensure_ascii=False`, indent 2. Detail payloads are the bare record.
- `jsonl`: one record per line, same order as the table — for streaming into
  `jq`/scripts.
- `table`: aligned columns, `·` for missing values, unicode-width-aware
  padding, titles truncated with `…`. Print `engine: <which> · N items`
  as a footer line — users must always know which engine answered.
- `md`: bullets ready to paste into notes/PRs.

Include in every record: stable **id**, **permalink/url** (so output chains
into the next command), **timestamps as epoch + human-readable**, and a
`<field>_source` marker when data comes from a fallback engine (live vs
archived, primary vs mirror).

## Exit codes

| code | meaning | caller behavior |
|---|---|---|
| 0 | ok | parse stdout |
| 1 | unexpected error | show stderr, stop |
| 2 | usage error | fix argv |
| 3 | rate-limited / blocked | sleep ≥60s or switch engine |
| 4 | not found / empty | refine query, don't retry |

## Cache, throttle, retry

- Cache dir: `~/.cache/any2cli/<tool>/`, one JSON blob per URL (sha256 name),
  `{ts, url, body}`. Default TTL 300s for listings, longer for immutable
  records (a post by id never changes much — 24h is fine). `--fresh`
  bypasses, `--cache-ttl 0` disables writes.
- Throttle: track last-hit timestamp per host **on disk** so consecutive
  process invocations also respect the interval (5s/req is a safe anonymous
  default; 1–2s for APIs designed for it). Add ±10% jitter. Cap the maximum
  sleep (~25s) so single commands never hang.
- Retry: 3 attempts. 429 → sleep `Retry-After` (clamped 10–60s) then retry;
  still 429 after retries → **switch engines or exit 3**, never hammer.
  5xx → exponential backoff. 404 → exit 4 immediately, no retry.

## Process rules

- Single file, executable, `#!/usr/bin/env python3` (or bash/node), stdlib
  only. If a dependency is unavoidable (playwright), import it lazily and
  degrade with a clear message when missing.
- stderr for diagnostics: engine switches, throttle sleeps (with `-v`),
  errors. stdout must parse.
- Secrets from env/config files only, never argv or hardcode.
- `--version`; `--help` epilog with 5+ real example invocations.
- If the source is anonymous read-only, say so in the help text; if a
  fallback's values are archived/approximate (scores at ingest time), say so
  in the output footer and record fields — approximation must be visible.

## Verification checklist (run before calling a CLI done)

1. Every subcommand runs live and exits 0 with real data.
2. Piped output is valid JSON (`... | python3 -m json.tool`).
3. Exit code 3 path: throttle/rate-limit actually triggers the fallback.
4. Exit code 4 path: a garbage id/query returns 4, not a traceback.
5. Cache: second identical run makes no network request (`-v` shows it).
6. Table renders with no ragged columns when titles contain CJK/emoji.
7. `--limit` is honored; `--format jsonl|md` produce sane output.
