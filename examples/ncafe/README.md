# ncafe — 익명 네이버 카페 검색 CLI

계정 없이, API 키 없이, Python 3 표준 라이브러리만으로 네이버 카페를
검색한다. any2cli 컨트랙트 준수 (table/json/jsonl/md, exit 0/2/3/4,
디스크 캐시+스로틀, 멀티엔진 폴백).

## 사용

```bash
ncafe search 캠핑                        # 모든 카페의 게시글 검색 (관련도순)
ncafe search 캠핑 --sort date            # 최신순
ncafe search 캠핑 --date week            # 최근 1주
ncafe search 캠핑카 --where trade        # 거래글만
ncafe cafes 레트로게임                   # 카페 찾기: 이름+설명 매칭, 멤버수/랭킹/글수
ncafe cafes 캠핑 --format json           # 에이전트용 JSON
```

`search`는 **전체 네이버 카페를 대상**으로 한 쿼리로 검색한다 (cafe_where='',
"모든 카페에서 검색"). `cafes`는 **카페 설명글까지 검색 타깃**에 포함해서
목적에 맞는 카페 자체를 찾는다 — 멤버수·카페랭킹·새글수·전체글수·설명이
함께 나온다.

출력 레코드 (json):
- article: `{id, title, url, cafe, cafe_url, date, snippet, thumb, official}`
- cafe: `{id, name, url, members, rank_tier, new_posts, total_posts, description}`

## 엔진

| 엔진 | 소스 | 특징 |
|---|---|---|
| ssearch | `s.search.naver.com/p/cafe/48/...` 무한스크롤 XHR | 기본. JSON+HTML 프래그먼트 |
| www | `search.naver.com/search.naver` SSR HTML | 폴백. 소프트 레이트리밋 시 자동 전환 |

소프트 레이트리밋(200+빈 body) 감지 → 9s×3 재시도 → www 전환 → exit 3.
기본 스로틀 6s/호스트(디스크 저장), 캐시 300s (`--fresh` 무시, `NCAFE_VERBOSE=1` 진단).

## 상태

- smoke-test 9/9 통과 (2026-09-19 실호출: 엔진·레코드 스키마·캐시·exit code)
- 한계: 호출당 1페이지(약 30개) — 네이버가 브라우저 세션 토큰(nlu_query) 없는
  start 페이지네이션을 무시함. 개별 카페 내부 검색/본문 전체는 범위 밖(로그인 필요).
- 전체 실측 기록: [KNOWHOW.md](KNOWHOW.md)
