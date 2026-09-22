#!/usr/bin/env bash
# smoke-test for mailplug — live-runs every subcommand and checks the contract.
# Requires: authenticated Chrome CDP on 9222 (cloned profile logged into gw.mailplug.com).
set -u
MP="${MP:-$(dirname "$0")/mailplug}"
pass=0; fail=0

check() {
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi
}

# 1. folders: live, exit 0, count > 0
"$MP" folders --format json >/dev/null 2>&1
check "folders live exit 0" $?
"$MP" folders --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>0, 'no folders'
assert d['engine']=='web-api'
sys.exit(0)"
check "folders shape" $?

# 2. list inbox: items > 0, record shape
"$MP" list inbox --limit 5 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>0, 'no items'
it=d['items'][0]
for k in ('id','subject','from','date','unread'):
    assert k in it, (k, it)
sys.exit(0)"
check "list record shape" $?

# 3. unread flag semantics: read-msg marked Y shows unread=False after mark-read
INBOX_JSON=$(MAILPLUG_FRESH=1 "$MP" list inbox --limit 5 --format json 2>/dev/null)
echo "$INBOX_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
flags=[(i['id'], i['unread']) for i in d['items']]
# only sanity: booleans present
assert all(isinstance(u,bool) for _,u in flags)
sys.exit(0)"
check "unread flag booleans" $?

# 4. search narrows results
"$MP" list inbox --search 콘텐츠랩 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']>=1, 'search empty'
assert any('콘텐츠랩' in (i['subject'] or '') for i in d['items']), 'keyword not in subjects'
sys.exit(0)"
check "search filters" $?

# 5. read detail: subject + body_text
FIRST_ID=$(echo "$INBOX_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['items'][0]['id'])")
"$MP" read "$FIRST_ID" --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('subject'), 'no subject'
assert isinstance(d.get('body_text'), str), 'no body_text'
sys.exit(0)"
check "read detail shape" $?

# 6. send dry-run: payload only, no network send
"$MP" send mcpark@livemolo.me --subject cli-smoke --body x --dry-run 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['transferMode']=='send'
assert d['toRecipients'][0]['emailAddress']=='mcpark@livemolo.me'
sys.exit(0)"
check "send dry-run payload" $?

# 7. garbage message id -> exit 4
"$MP" read 99999 --format json >/dev/null 2>&1
[ $? -eq 4 ]
check "garbage message id -> exit 4" $?

# 8. cache hit on rerun
MAILPLUG_VERBOSE=1 "$MP" list inbox --limit 3 --format json 2>&1 >/dev/null | grep -q "cache hit"
check "cache hit on rerun" $?

# 9. jsonl line count
N=$(("$("$MP" list inbox --limit 3 --format jsonl 2>/dev/null | wc -l)"))
[ "$N" -eq 3 ]
check "jsonl line count" $?

# 10. live send + arrival (self-addressed: lands in 'self' 내게쓴 편지함, per live test)
OUT=$("$MP" send mcpark@livemolo.me --subject "cli-smoke $(date +%s)" --body "smoke" 2>/dev/null)
echo "$OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('sent') is True, d
assert d.get('message_id'), d
sys.exit(0)"
check "live send accepted" $?
# 10b. response must be honest: no messageId → sent:false + exit 2 (schema change canary)
echo "$OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert set(d) >= {'sent','message_id','error'}, d.keys()
sys.exit(0)"
check "send response schema" $?
sleep 4
MAILPLUG_FRESH=1 "$MP" list self --limit 5 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert any((i['subject'] or '').startswith('cli-smoke') for i in d['items']), 'sent mail not in self folder'
sys.exit(0)"
check "sent mail arrived (self folder)" $?

# 11. mark-read round-trip on a known unread message
TARGET=$(MAILPLUG_FRESH=1 "$MP" list inbox --limit 10 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
u=[i['id'] for i in d['items'] if i['unread']]
print(u[0] if u else '')")
if [ -n "$TARGET" ]; then
  "$MP" read "$TARGET" --mark-read --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('marked_read') is True
sys.exit(0)"
  check "mark-read call ok" $?
  MAILPLUG_FRESH=1 "$MP" list inbox --limit 10 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
t=int('$TARGET')
me=[i for i in d['items'] if i['id']==t]
assert me and me[0]['unread'] is False, 'server flag not Y'
sys.exit(0)"
  check "mark-read server-side" $?
else
  echo "skip mark-read round-trip (no unread message available)"
fi

# 3. pagination: --page 2 disjoint from page 1 (offset 실측 동작)
python3 - << 'EOF'
import subprocess, json, sys, os
MP = os.path.expanduser("~/.agents/skills/any2cli/examples/mailplug/mailplug")
env = dict(os.environ); env["MAILPLUG_TTL"] = "0"
p1 = json.loads(subprocess.run([MP,"list","inbox","--limit","10","--page","1","--format","json"],capture_output=True,text=True,env=env).stdout or "{}")
p2 = json.loads(subprocess.run([MP,"list","inbox","--limit","10","--page","2","--format","json"],capture_output=True,text=True,env=env).stdout or "{}")
s1 = set(i["id"] for i in p1.get("items",[]))
s2 = set(i["id"] for i in p2.get("items",[]))
assert s1 and s2, "empty page"
assert not (s1 & s2), "pages overlap: %s" % (s1 & s2)
sys.exit(0)
EOF
check "pagination page2 disjoint" $?

# 3b. page beyond end -> empty, not error
"$MP" list inbox --limit 10 --page 99 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['count']==0, 'page99 should be empty'
sys.exit(0)"
check "page beyond end empty" $?

# 12. invalid recipient -> exit 2 + stderr message (반증: 200 오탐 방지)
OUT=$("$MP" send "not-an-email" --subject probe --body x 2>/tmp/mp_send_err.txt)
CODE=$?
grep -q "발송 거부" /tmp/mp_send_err.txt && [ "$CODE" -eq 2 ]
check "invalid recipient -> exit 2 + msg" $?

# 13. read shows sender (from 병합)
"$MP" read 36 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('from'), 'read missing from: %s' % d.get('from')
sys.exit(0)"
check "read includes sender" $?

# 14. cookie cache file permission 600
"$MP" folders >/dev/null 2>&1
PERM=$(stat -c %a ~/.cache/any2cli/mailplug/cookies.json 2>/dev/null)
[ "$PERM" = "600" ]
check "cookie file 0600" $?

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
