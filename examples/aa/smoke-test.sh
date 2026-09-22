#!/bin/bash
# aa CLI smoke-test v2 — 구조화 flight 기반. 모든 서브커맨드 실호출 게이트.
set -u
DIR="$(dirname "$(readlink -f "$0")")"
AA="$DIR/aa"
fail=0
chk() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3 (want=$1 got=$2)"; fail=1; fi }

# 0) 구버전 캐시 클리어 (v1과 파일 포맷 동일하므로 스키마 검증이 캐시를 오염시키지 않도록 fresh로 시작)
rm -rf ~/.cache/aa-cli

# 1) models
$AA models --format json >/dev/null 2>&1; chk 0 $? 'models exit 0'
n=$($AA models --format json 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
[ "$n" -ge 25 ] 2>/dev/null; chk 0 $? "models count>=25 (got=$n)"

# 2) model raw — currentModel 레코드 무결성
$AA model glm-5-3 --raw 2>/dev/null | python3 -c "
import json,sys
r=json.load(sys.stdin)
assert r['slug']=='glm-5-3', 'slug'
assert abs(r['intelligenceIndex']-44.777)<0.01, 'II'
assert r['parameters']==753 and r['inferenceParametersActiveBillions']==40, 'params'
assert r['contextWindowTokens']==1000000, 'ctx'
assert r['price1mInputTokens']==1.4 and r['price1mOutputTokens']==4.4, 'price'
pb=r['performanceByPromptType']; assert pb['long']['medianOutputSpeed']>50, 'long tps'
ev=r['intelligenceIndexEvaluations']; assert len(ev)>=10 and all('timePerTask' in e for e in ev), 'evals'
assert isinstance(r['intelligenceIndexTimePerTask'],(int,float)) and r['intelligenceIndexTimePerTask']>0, 'ii time'
print('raw record OK: II=%.2f, long tps=%.1f, evals=%d' % (r['intelligenceIndex'], pb['long']['medianOutputSpeed'], len(ev)))
"; chk 0 $? 'model glm-5-3 raw record'

# 3) summary
$AA summary glm-5-3 glm-5-3-flash --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert len(d)==2, 'rows'
a,b=d
assert a['name'].startswith('GLM-5.3') and b['name'].startswith('GLM-5.3-Flash')
assert a['out_tps'] and b['out_tps'] and a['out_tps']!=b['out_tps'], 'tps differ'
assert a['ii_time_per_task_s'] and b['ii_time_per_task_s'], 'task time'
print('summary OK:', a['name'], a['out_tps'], 'vs', b['name'], b['out_tps'])
"; chk 0 $? 'summary 5.3 vs flash'

# 4) tasks — timePerTask 존재
$AA tasks glm-5-3 --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert len(d)>=10, 'evals count'
assert all(e['time_per_task_s'] for e in d), 'time per task all present'
mx=max(d, key=lambda e:e['time_per_task_s'])
print('tasks OK: slowest=%s %.0fs' % (mx['bench'], mx['time_per_task_s']))
"; chk 0 $? 'tasks timePerTask'

# 5) speed — prompt type별
$AA speed glm-5-3-flash --format json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
ptypes={e['ptype'] for e in d}
assert 'medium' in ptypes and 'long' in ptypes, 'ptypes'
print('speed OK:', sorted(ptypes))
"; chk 0 $? 'speed by prompt type'

# 6) search
out=$($AA search glm --format json 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
chk 2 "$out" 'search glm hits=2'

# 7) 캐시 히트
eng=$($AA model glm-5-3 --raw 2>&1 >/dev/null | grep -o 'engine=[a-z]*')
[ "$eng" = "engine=cache" ]; chk 0 $? "cache hit ($eng)"

# 8) --fresh 관통
eng=$($AA model glm-5-3 --raw --fresh 2>&1 >/dev/null | grep -o 'engine=[a-z]*')
[ "$eng" = "engine=net" ]; chk 0 $? "--fresh engine=net ($eng)"

# 9) 쓰레기 슬러그 → 4
$AA model not-a-real-model-xyz >/dev/null 2>&1; chk 4 $? '404 exit 4'
# 10) search 무결과 → 3
$AA search zzzznotexist >/dev/null 2>&1; chk 3 $? 'no-hit exit 3'

exit $fail
