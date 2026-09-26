#!/usr/bin/env bash
# x-cli smoke test — every subcommand live-called. Run: bash smoke-test.sh
set -u
PASS=0; FAIL=0
t2() { # t2 <desc> "allowed_exits space-sep" <cmd...> — for engines that may be temporarily blocked
  local desc="$1" wants="$2"; shift 2
  "$@" >/dev/null 2>&1; local ec=$?
  if echo " $wants " | grep -q " $ec "; then PASS=$((PASS+1)); echo "ok   [$ec] $desc";
  else FAIL=$((FAIL+1)); echo "FAIL [$ec want $wants] $desc"; fi
}
t() { # t <desc> <want_exit> <cmd...>
  local desc="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local ec=$?
  if [ "$ec" = "$want" ]; then PASS=$((PASS+1)); echo "ok   [$ec] $desc";
  else FAIL=$((FAIL+1)); echo "FAIL [$ec want $want] $desc"; fi
}

cd "$(dirname "$0")"
X=./x

t "tweet synd (thdxr reply)"        0 $X tweet 2102940691521569207 --format json
t "tweet synd url form"             0 $X tweet "https://x.com/pengsonal/status/2103538654459449367" --format json
t "tweet synd missing -> 4"         4 $X tweet 999999999999999999999 --format json
t "tweet no arg -> 2"               2 $X tweet
t "tweet cdp (views+metrics)"       0 $X tweet 2103538654459449367 --cdp --format json --fresh
t "replies cdp"                     0 $X replies 2103538654459449367 --format json --fresh
t "user cdp (pengsonal)"            0 $X user pengsonal --format json --fresh
t2 "search google-cdp (3=google captcha)" "0 3" $X search glm-5.5-flash --format json --fresh
t2 "search enrich (synd)" "0 3" $X search glm-5.5-flash --enrich --fresh --format json
t2 "search garbage (4, or 3 if captcha)" "4 3" $X search zzz_qqq_nonexistent_xyz --format json --fresh
t "unknown subcmd -> 2"              2 $X tweetnotauser --format json

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
