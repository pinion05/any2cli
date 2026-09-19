#!/usr/bin/env bash
# smoke-test.sh — live verification for the reddit CLI (any2cli example).
# Runs each subcommand once, checks exit codes and output sanity.
# Be gentle: this makes ~10 network hits (RSS budget) — do not loop it.
#
#   ./smoke-test.sh            # run all
#   ./smoke-test.sh -v         # CLI verbose too
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/reddit"
VERBOSE="${1:-}"
VFLAG=""
[ "$VERBOSE" = "-v" ] && VFLAG="-v"
PASS=0; FAIL=0

check() {  # check <name> <expect_exit> <cmd...>
  local name="$1" expect="$2"; shift 2
  local out rc
  out=$("$@" 2>/tmp/smoke-stderr.txt); rc=$?
  if [ "$rc" -eq "$expect" ]; then
    printf 'PASS  %-28s exit=%d\n' "$name" "$rc"; PASS=$((PASS+1))
  else
    printf 'FAIL  %-28s exit=%d (want %d)\n' "$name" "$rc" "$expect"
    sed 's/^/      stderr: /' /tmp/smoke-stderr.txt | head -3
    FAIL=$((FAIL+1))
  fi
  LAST_OUT="$out"
}

json_ok() {  # json_ok <name>
  if printf '%s' "$LAST_OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    printf 'PASS  %-28s valid json\n' "$1"; PASS=$((PASS+1))
  else
    printf 'FAIL  %-28s invalid json\n' "$1"; FAIL=$((FAIL+1))
  fi
}

has() {  # has <name> <pattern>
  if printf '%s' "$LAST_OUT" | grep -q "$2"; then
    printf 'PASS  %-28s contains %s\n' "$1" "$2"; PASS=$((PASS+1))
  else
    printf 'FAIL  %-28s missing %s\n' "$1" "$2"; FAIL=$((FAIL+1))
  fi
}

# --- usage / offline paths (no network) ------------------------------------
check "usage-error exit 2"      2 "$R" posts
check "bad id exit 2"           2 "$R" post "not a valid id!!"
check "version"                 0 "$R" --version

# --- live paths --------------------------------------------------------------
check "post detail (arctic)"    0 "$R" post 1w78kp5 $VFLAG
has   "post has score field"    '"score"'
has   "post has upvote_ratio"   '"upvote_ratio"'

check "comments (tree+scores)"  0 "$R" comments 1w78kp5 --limit 10 --format json $VFLAG
json_ok "comments json"

check "subreddit listing"       0 "$R" posts r/python --limit 5 --format json $VFLAG
json_ok "listing json"
has   "listing has engine"      '"engine"'
# subreddit field must agree with the permalink (catches name-mangling bugs
# like lstrip("r/") turning r/retroid into "etroid")
if printf '%s' "$LAST_OUT" | python3 -c '
import json, sys, re
d = json.load(sys.stdin)
bad = [p["id"] for p in d.get("posts", [])
       if p.get("subreddit") and p.get("permalink")
       and not re.search(r"/r/%s/" % re.escape(p["subreddit"]), p["permalink"],
                         re.I)
       and not p["permalink"].split("/r/")[1].startswith(("u/", "u_"))]
sys.exit(1 if bad else 0)' 2>/dev/null; then
  printf 'PASS  %-28s subreddit==permalink\n' "listing sub check"; PASS=$((PASS+1))
else
  printf 'FAIL  %-28s subreddit/permalink mismatch\n' "listing sub check"; FAIL=$((FAIL+1))
fi

check "in-sub search"           0 "$R" search asyncio --sub python --limit 5 --format json $VFLAG
check "global search"           0 "$R" search playwright --limit 5 --format json $VFLAG
check "subreddit search"        0 "$R" subs "machine learning" --limit 5 --format json $VFLAG
check "user history"            0 "$R" user spez --limit 5 --format json $VFLAG

# cache proof: second identical run hits no network (verbose prints cache hits)
if OUT=$("$R" post 1w78kp5 -v 2>&1) && echo "$OUT" | grep -q "cache hit"; then
  printf 'PASS  %-28s second run cached\n' "cache"; PASS=$((PASS+1))
else
  printf 'FAIL  %-28s no cache hit on rerun\n' "cache"; FAIL=$((FAIL+1))
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
