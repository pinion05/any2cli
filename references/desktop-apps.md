# Wrapping a desktop app into a CLI

Desktop apps are data sources too — chat clients, media players, IDEs,
native tools. The CLI talks to the app through whatever control surface the
OS exposes and prints what it found. Same contract as every other wrapper.

## Pick the surface (cheapest that reaches the data)

| Surface | Works for | Cost / notes |
|---|---|---|
| App's own CLI/URL scheme | apps with `foo://` handlers or bundled binaries | always try `app --help` first |
| Local API / socket | Electron apps, Spotify, Docker Desktop | devtools → Network on localhost; often unauthenticated |
| CDP (Chrome DevTools Protocol) | Electron apps specifically | `app --remote-debugging-port=9222`, then it's a website problem — reuse website-playwright patterns |
| AppleScript / JXA | macOS apps with scripting dictionaries | `osascript -e 'tell app "X" to …'`; `sdef app.app > x.sdef` to list what's scriptable |
| Accessibility tree | everything else | the universal fallback; screen-reader API sees the real UI tree |
| File watching | apps that persist state (sqlite/json logs) | read the app's database directly; watch for locks |

## Probe sequence

1. `sdef /Applications/App.app` (macOS) — does it expose scripting? Which
   objects/commands?
2. Look for local endpoints: `lsof -i -P | grep -i <appname>` — listening
   ports on localhost are usually an internal API.
3. Electron? Check for CDP: relaunch with `--remote-debugging-port=9222`
   and curl `http://127.0.0.1:9222/json` — if the app's renderer is there,
   drive it like a webpage (often there's a redux/store endpoint).
4. Find the data on disk: `ls ~/Library/Application\ Support/<App>` —
   sqlite/json state read directly is the fastest CLI of all.
5. Accessibility tree only when 1-4 fail (cua-driver CLI in this environment
   snapshots trees, clicks/keys by element index — no screenshots needed).

## Patterns

**AppleScript read (macOS, synchronous, no UI focus needed for most reads):**

```bash
osascript -e 'tell application "Spotify" to name of current track'
osascript -e 'tell application "Messages" to name of every chat'   # gated by TCC
```

Wrap as: `appcli now-playing --format json` → `{"track": "...", ...}`.
TCC permission prompts appear once, to the human, at first run — that's
fine, document it in the README.

**Electron over CDP:**

```bash
/Applications/Slack.app/Contents/MacOS/Slack --remote-debugging-port=9222 &
curl -s http://127.0.0.1:9222/json | python3 -c 'import json,sys;[print(t["url"]) for t in json.load(sys.stdin)]'
# then playwright.connect_over_cdp("http://127.0.0.1:9222") and reuse DOM patterns
```

The agent-browser skill in this environment wraps this exact flow (including
Electron specifics) — prefer it over hand-rolling CDP.

**State file watch:**

```bash
sqlite3 ~/Library/Application\ Support/SomeApp/db.sqlite \
  "select id,title,updated from items order by updated desc limit 20;"
```

Often the *best* CLI: no UI automation at all, pure read. Check write
locks (copy the db to /tmp before querying if the app holds it).

## Rules

- Desktop wrapping is for READING and simple actions. Never script
  destructive actions (delete, send, pay) without an explicit `--yes`
  confirmation flag and a dry-run default.
- Respect focus: AppleScript/UI automation can steal the user's keystrokes.
  Prefer local APIs and state files — they don't touch the foreground.
- Expect breakage on app updates: pin selectors/queries defensively, test in
  the verify step, and fail loud (exit 1 with what changed) rather than
  returning empty data.
- The app must be running for live surfaces (CDP, AppleScript 'tell');
  state-file reads work when it's closed. Say which in `--help`.
