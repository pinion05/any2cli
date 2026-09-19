#!/usr/bin/env bash
# smoke-test for dc — live-runs every subcommand and checks the contract.
set -u
DC="${DC:-$(dirname "$0")/dc}"
pass=0; fail=0

check() {
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi
}

# 1. posts: live, exit 0, items > 0, notices stripped
out=$("$DC" posts programming --limit 5 --format json 2>/dev/null)
[ $? -eq 0 ] && echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>0, 'no items'
assert d['engine']=='ssr-list'
sys.exit(0)"
check "posts live" $?

# 2. record shape: num/url/title/nick/date/views/recommends/comments
"$DC" posts programming --limit 3 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
it=d['items'][0]
for k in ('num','url','title','nick','date','views','recommends','comments'):
    assert k in it, (k, it)
assert str(it['url']).startswith('https://gall.dcinside.com/board/view/')
sys.exit(0)"
check "post record shape" $?

# 3. pagination: page 2 disjoint from page 1
python3 - << 'EOF'
import subprocess, json, sys, os
env = dict(os.environ)
n1 = json.loads(subprocess.run([os.path.expanduser("~/.agents/skills/any2cli/examples/dc/dc"),"posts","programming","--page","1","--limit","25","--format","json"],capture_output=True,text=True,env=env).stdout or "{}")
os.environ["DC_TTL"]="0"; env["DC_TTL"]="0"
n2 = json.loads(subprocess.run([os.path.expanduser("~/.agents/skills/any2cli/examples/dc/dc"),"posts","programming","--page","2","--limit","25","--format","json"],capture_output=True,text=True,env=env).stdout or "{}")
s1 = set(i["num"] for i in n1.get("items",[]))
s2 = set(i["num"] for i in n2.get("items",[]))
sys.exit(0 if s1 and s2 and not (s1 & s2) else 1)
EOF
check "pagination page2 disjoint" $?

# 4. search: keyword actually filters (titles or result count differ)
"$DC" search programming 파이썬 --limit 10 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>0 and d['count']<25, 'search should be narrower than full list'
assert any('파이썬' in (i['title'] or '') for i in d['items']), 'no keyword in titles'
sys.exit(0)"
check "search filters" $?

# 5. post detail: title + body + comments shape
"$DC" post programming 2939751 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('title'), 'no title'
assert d.get('body_text'), 'no body'
assert isinstance(d.get('comments'), list), 'no comments array'
sys.exit(0)"
check "post detail shape" $?

# 6. minor gallery
"$DC" posts minor:ai --limit 3 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>0, 'minor gallery empty'
assert '/mgallery/' in d['items'][0]['url'], d['items'][0]['url']
sys.exit(0)"
check "minor gallery (mgallery)" $?

# 7. garbage gallery -> exit 4
"$DC" posts nosuchgallery12345 --format json >/dev/null 2>&1
[ $? -eq 4 ]
check "garbage gallery -> exit 4" $?

# 8. cache: second run hits cache
DC_VERBOSE=1 "$DC" posts programming --limit 3 --format json 2>&1 >/dev/null | grep -q "cache hit"
check "cache hit on rerun" $?

# 9. jsonl lines
[ "$("$DC" posts programming --limit 3 --format jsonl 2>/dev/null | wc -l)" -eq 3 ]
check "jsonl line count" $?

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
