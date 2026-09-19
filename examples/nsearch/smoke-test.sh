#!/usr/bin/env bash
# smoke-test for nsearch — live-runs subcommands and checks the contract.
set -u
NS="${NS:-$(dirname "$0")/nsearch}"
pass=0; fail=0

check() {
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi
}

# 1. news: live, items > 0
out=$("$NS" news 인공지능 --limit 5 --format json 2>/dev/null)
[ $? -eq 0 ] && echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>0 and d['engine']=='news-more-json'
sys.exit(0)"
check "news live" $?

# 2. news record shape
"$NS" news 인공지능 --limit 3 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
it=d['items'][0]
for k in ('title','url','press','date'): assert k in it, (k,it)
assert it['url'].startswith('http')
sys.exit(0)"
check "news record shape" $?

# 3. news pagination: start=11 mostly new titles
python3 - << 'EOF'
import subprocess, json, sys, os
NS=os.path.expanduser("~/.agents/skills/any2cli/examples/nsearch/nsearch")
env=dict(os.environ); env["NSEARCH_TTL"]="0"
p1=json.loads(subprocess.run([NS,"news","인공지능","--limit","20","--format","json"],capture_output=True,text=True,env=env).stdout)
p2=json.loads(subprocess.run([NS,"news","인공지능","--start","11","--limit","20","--format","json"],capture_output=True,text=True,env=env).stdout)
s1=set(i["title"] for i in p1.get("items",[]))
s2=set(i["title"] for i in p2.get("items",[]))
sys.exit(0 if s1 and s2 and len(s1&s2) < len(s2)//2 else 1)
EOF
check "news start=11 shifts results" $?

# 4. sort=recent gives fresher dates than sort=rel
"$NS" news 인공지능 --sort recent --limit 5 --format json 2>/dev/null | python3 -c "
import json,sys,re
d=json.load(sys.stdin)
fresh=sum(1 for i in d['items'] if i.get('date') and re.search(r'(시간|분) 전', i['date']))
sys.exit(0 if fresh >= 3 else 1)"
check "sort=recent freshness" $?

# 5. days=7 period filter returns only recent-ish items
"$NS" news 인공지능 --days 7 --sort recent --limit 5 --format json 2>/dev/null | python3 -c "
import json,sys,re
d=json.load(sys.stdin)
bad=[i['date'] for i in d['items'] if i.get('date') and re.search(r'\d+\s*(주|개월|년)\s*전', i['date'])]
sys.exit(0 if not bad and d['count']>0 else 1)"
check "days=7 filter" $?

# 6. blogs: >=2 items with blog.naver.com urls
"$NS" blogs 인공지능 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>=2, d['count']
for i in d['items']: assert 'blog.naver.com' in i['url'], i['url']
sys.exit(0)"
check "blogs live + url shape" $?

# 7. garbage query -> exit 4
"$NS" news "zzxxqq 없는검색어테스트" --format json >/dev/null 2>&1
[ $? -eq 4 ]
check "empty news -> exit 4" $?

# 8. cache hit on rerun
NSEARCH_VERBOSE=1 "$NS" news 인공지능 --limit 3 --format json 2>&1 >/dev/null | grep -q "cache hit"
check "cache hit on rerun" $?

# 9. jsonl lines
[ "$("$NS" news 인공지능 --limit 4 --format jsonl 2>/dev/null | wc -l)" -eq 4 ]
check "jsonl line count" $?

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
