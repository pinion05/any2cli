# aa — Artificial Analysis 익명 읽기 CLI

계정·API 키 없이 artificialanalysis.ai의 모델 벤치마크 데이터를 조회한다.
데이터 표면: `/models/<slug>` SSR HTML의 Next.js flight에 인라인된 `currentModel`
풀 레코드(80+ 필드)를 정규식 언이스케이프 + brace-match로 추출. JSON API/XHR은 없음(프로브 실측).

## 설치
```bash
ln -sf ~/.agents/skills/any2cli/examples/aa/aa ~/.local/bin/aa
```

## 명령
```bash
aa models                                   # 등록 슬러그 전체 (인덱스 카드 스캔)
aa search glm                               # 슬러그 부분검색
aa model glm-5-3 [--raw]                    # 전체 레코드 (raw=원본 JSON)
aa summary glm-5-3 glm-5-3-flash            # 핵심 지표 요약 표
aa tasks glm-5-3 glm-5-3-flash              # 벤치마크별 작업 소요시간·비용 (timePerTask)
aa speed glm-5-3-flash                      # 프롬프트 타입별 속도/지연 (medium/long/hundredK/parallel)
```
공통 플래그: `--format table|json|jsonl|md` · `--cache-ttl 초` (기본 3600) · `--fresh` (캐시 우회)

Exit codes: `0` 정상 · `2` 네트워크 · `3` 결과 없음 · `4` AA 미등록 슬러그(404)

## 표현 필드 (summary)
`ii` Intelligence Index · `out_tps` long-프롬프트 중앙 출력속도 · `ttft_s` ·
`e2e_500tok_s` 500토큰 응답 시간 · `ii_time_per_task_s` II 과제당 평균 소요(초) ·
`ii_cost_per_task` II 과제당 비용 · 가격/컨텍스트/파라미터/라이선스.

## 한계
- AA 미등록 신모델(glm-5-3-flashx 등)은 404 → exit 4.
- 캐시 파일은 `~/.cache/aa-cli/` (URL 키 160자 해시).
- flight 구조가 바뀌면 `extract_model_record` 재검증 필요 (smoke-test가 자동 점검).
