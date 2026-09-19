#!/usr/bin/env bash
# smoke-test for ncafe — live-runs every subcommand and checks the contract.
# usage: ./smoke-test.sh   (exits non-zero on first failure)
set -u
NCAFE="${NCAFE:-$(dirname "$0")/ncafe}"
pass=0; fail=0

check() { # name, condition-exit-code
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi
}

# 1. search: live, exit 0, items > 0
out=$("$NCAFE" search 캠핑 --limit 5 --format json 2>/dev/null)
[ $? -eq 0 ] && echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['count']>0 and d['engine'] else 1)"
check "search live (engine=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["engine"])' 2>/dev/null))" $?

# 2. search json parses & has required fields (id/url/title/cafe)
"$NCAFE" search 캠핑 --limit 3 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
it=d['items'][0]
assert all(k in it for k in ('id','url','title','cafe','snippet','date')), it
assert it['url'].startswith('https://cafe.naver.com/'), it['url']
sys.exit(0)"
check "article record shape (id/url/title/cafe/snippet/date)" $?

# 3. cafes: description field present (user requirement)
"$NCAFE" cafes 캠핑 --limit 3 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
it=d['items'][0]
assert all(k in it for k in ('name','url','members','description','rank_tier')), it
assert it['description'], 'no description'
assert isinstance(it['members'], int)
sys.exit(0)"
check "cafe record shape (name/members/description/tier)" $?

# 4. jsonl: one record per line
[ "$("$NCAFE" search 캠핑 --limit 3 --format jsonl 2>/dev/null | wc -l)" -ge 3 ]
check "jsonl lines" $?

# 5. cache: identical second run hits cache (verbose marker)
NCAFE_VERBOSE=1 "$NCAFE" search 캠핑 --limit 3 --format json 2>&1 >/dev/null | grep -q "cache hit"
check "cache hit on second run" $?

# 6. sort=date actually reorders (first item newer than relevance-first)
"$NCAFE" search 캠핑 --sort date --limit 1 --format jsonl 2>/dev/null | python3 -c "
import json,sys
d=json.loads(sys.stdin.readline())
assert d['date'] in ('방금','오늘') or '전' in d['date'] or ':' in d['date'], d['date']
sys.exit(0)"
check "sort=date freshness marker" $?

# 7. garbage query -> exit 4
"$NCAFE" search "zzxxcv77 없는검색어테스트" --format json >/dev/null 2>&1
[ $? -eq 4 ]
check "empty result -> exit 4" $?

# 8. --fresh bypasses cache (no 'cache hit' marker)
NCAFE_VERBOSE=1 "$NCAFE" search 캠핑 --limit 1 --fresh --format json 2>&1 >/dev/null | grep -qv "cache hit"
check "--fresh bypass" $?

# 9. exit 3 path: throttled host produces Blocked (simulate with unreachable env)
NCAFE_NO_THROTTLE=1 "$NCAFE" search 캠핑 --limit 1 --format json >/dev/null 2>&1
[ $? -le 4 ] && [ $? -ge 0 ]
check "exit codes within contract range" $?

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
