# KNOWHOW — aa (Artificial Analysis CLI)

## 프로브 전 기록 (2026-09-22)

1. **JSON API 부재 실측**: `/api/models`, `/api/model-data`, `/api/models.json`, `/data/models.json`, `/api/v1/models` 전부 404. 페이지 XHR 관찰(CDP) → 정적 자산 외 요청 없음. 즉 데이터는 전부 SSR.
2. **FAQ 문장 1차 표면**: `generates output at 62.4 tokens per second` 등 정규식으로 가격·TTFT·파라미터 캡처 성공 → 익명 curl 재현 확인. 그러나 단위가 `t/s`가 아니라 `tokens per second`라 첫 스캔에서 놓침(교훈: 단위 문어체까지 검색할 것).
3. **flight 풀 레코드 발견**: `62.4` 전후 맥락 스캔에서 `self.__next_f.push` 청크 안에 `"currentModel":{...}` 객체(80+ 필드) 존재 확인. `intelligenceIndexEvaluations[]{timePerTask,costPerTask,outputTokensPerTask}`, `performanceByPromptType{medium,long,hundredK,mediumParallel}`, `outputSpeedVariance{p05..p95}`, `endToEndResponseTime`, 블렌디드 가격 5종 등 "모든 표와 수치"가 여기 들어있음(사용자 요구 '모든 표와 수치 등을 조회가능하게').
4. **추출 파이프라인**: flight 청크 regex → `json.loads('"'+chunk+'"')` 언이스케이프 → `"currentModel":{` brace-match(문자열 리터럴 escape 존중) → `json.loads`. `fp.rfind('{"slug"')`로 record start를 잡으면 이웃 eval 객체를 잘못 집는다 — 반드시 `"currentModel"` 앵커에서 시작할 것.
5. **모델 인덱스**: `/models`의 카드 `href="/models/<slug>"` 스캔. `capabilities`, `recommend`는 모델이 아니므로 제외. 29개 슬러그(26-09-22). GLM 계열: `glm-5-3`, `glm-5-3-flash`만 등록 — flashx는 AA 미등록(404).
6. **AA 수치 vs z.ai 코딩플랜 실측 차이**: AA long tps 62.4(5.3)는 z.ai 공용 API 기준. 코딩플랜 전용 엔드포인트 실측은 220 t/s로 3.5배 빠름 — AA 값은 'AA 측정 환경(공용 API)'의 값이지 코딩플랜 체감이 아님. 보고 시 측정 계정/엔드포인트를 반드시 병기.
7. **Flash 체감 재해석 데이터**: AA 기준 Flash(88 t/s) > 5.3(62.4 t/s), II 과제당 시간 Flash 666s < 5.3 980s. 즉 AA 공용 API에선 Flash가 빠른 게 맞고, 내 코딩플랜 실측(5.3 220 > Flash 111)과 방향이 반대 — z.ai가 코딩플랜 엔드포인트에 5.3 우선 배치를 다르게 하는 것으로 추정(추측 표기). 코딩플랜 체감은 로컬 실측값을 우선할 것.

## 실패 경로 (재프로브 절약)
- AA 스크래핑에 `t/s` 단위 regex만 쓰면 0힛 — 문어체 `tokens per second`.
- `hn.algolia` 스크래핑과 무관하게 AA flight는 3MB — 매 요청 파싱 비용 큼 → 디스크 캐시 필수(기본 1h).
- FlashX 슬러그 추측(`glm-5-3-flashx`) 금지 — 404 확정.

## smoke-test
`bash ~/.agents/skills/any2cli/examples/aa/smoke-test.sh` — models 카운트, raw 레코드 스키마(II/파라미터/가격/evals), summary/tasks/speed, 캐시 히트, --fresh 관통, 404→4, 무결과→3 전수 검증.
