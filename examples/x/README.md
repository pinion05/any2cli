# x — anonymous X/Twitter reader CLI

No account, no API key. Reads tweets, engagement, replies, user profiles,
and searches tweets via Google's index. Python 3 stdlib + CDP browser
(`agent-browser --cdp 9222`, set `ANY2CLI_X_CDP` to override).

```bash
x tweet 2102940691521569207                     # likes, replies, text (syndication, fast)
x tweet <id|url> --cdp                          # + views, reposts, bookmarks
x replies <id|url>                              # visible replies w/ per-reply likes
x user @pengsonal                               # profile: followers, bio, recent posts
x search "glm-5.5-flash"                        # tweet search (google site:x.com)
x search "glm-5.5-flash" --enrich               # + exact likes/date via syndication
```

All commands: `--format table|json|jsonl|md`, `--fresh` (bypass cache),
`--limit N`. TTY → table, pipe → JSON. Exit 0/2/3/4.

Engines: `synd` (cdn.syndication.twimg.com) → `cdp` (x.com anonymous render)
→ `google-cdp` (search). See KNOWHOW.md for probe log & limits.
