# x-cli KNOWHOW — probe log & design decisions

Anonymous X/Twitter reader. No account, no API key. Born 2026-09-26 from the
GLM-5.5-Flash rumor investigation (llm-release-tracking skill).

## Surface probes (all live-tested 2026-09-26)

| Surface | Result |
|---|---|
| `cdn.syndication.twimg.com/tweet-result?id=&token=x` | **LIVE** — text, author, likes (favorite_count), replies (conversation_count), parent tweet, verified flag. No views. ~0.3s. |
| same, `user-result` | 404 dead |
| `syndication.twitter.com/srv/timeline-profile/screen-name/X` | 429 rate-limited (widget embed path, no stable anonymous access) |
| x.com tweet page, plain HTTP | login wall |
| x.com tweet page, **CDP headful** (`?lang=en`) | **LIVE** — full text, views (조회수), replies/reposts/likes/bookmarks, replies with per-reply likes+views, quote tweets. JS-rendered but anonymous. |
| x.com user profile, CDP | **LIVE** — name, bio, posts, followers, following, joined, recent tweets w/ metrics |
| Google `site:x.com "query"` plain HTTP (desktop+mobile UA, gbv=1) | 200 but JS shell — zero results in HTML |
| Google `site:x.com` **CDP** | **LIVE** — ~10-20 results: author, status id, likes hint ("440+ likes"), relative time |
| Bing `site:x.com` RSS + HTML | ignores site: filter (returns generic GLM results) — rejected |
| DDG html.duckduckgo.com | works but thin (1 result); kept as future fallback, not wired |
| nitter.net / xcancel / poast.org | all down (instance graveyard) — rejected |
| syndication token param | `token=x` accepted blindly; `token=a` also works — not a real auth token |

## Design

- **Engines by freshness×cost**: `tweet` defaults to synd (fast, exact likes) —
  `--cdp` switches to browser engine for views/bookmarks/replies.
  `search` = google-cdp (only working anonymous search path).
- **`?lang=en` forced** on all x.com CDP opens — parsing against Korean
  locale ("조회수", "팔로워") is locale-fragile; en gives stable "Views"/"Followers".
  Number suffixes still parsed for both locales (K/M/B + 만/천/억).
- **U+00A0 trap**: Google innerText separators are `X\u00a0·\u00a0author` —
  NBSP, which Python `\s` does NOT match (`[...]likes? · [...]` silently
  failed until codepoint dump revealed 160,183). All separator regexes use
  `[\s\u00a0]`.
- **CDP eval JSON round-trip**: `agent-browser eval` prints a JSON-quoted
  string; `JSON.stringify(...)` payload → `json.loads(json.loads(out))`.
  Retries twice on non-JSON (page still loading).
- CDP tabs are shared state — sequential use only; the CLI never closes tabs.

## Known limits (documented, not faked)

- **Google captcha**: automated search bursts trip `/sorry/` (verified
  2026-09-26 after ~10 queries). CLI detects it and exits **3** (blocked) —
  NOT 4 — so callers sleep instead of treating as no-results. Usually lifts
  in ~1h. Bing/DDG do NOT index x.com statuses (live-verified), so there is
  no fallback search engine; only the CDP x.com surfaces keep working during
  a google block.
- Views/bookmarks/reply-likes need the CDP engine (syndication has none).
- Replies list = what renders before the login-wall truncation (~3-10 top
  replies). Deep pagination requires login — not implemented.
- Search coverage = what Google indexed (recency-biased, misses some tweets;
  `--enrich` backfills exact likes/date via syndication for top 10).
- likes_hint from Google is a lower bound ("440+" → 440).
- User timeline pagination (beyond ~3 recent posts) not implemented.
