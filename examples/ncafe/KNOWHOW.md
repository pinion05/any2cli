# ncafe CLI 노하우 — 네이버 카페 검색 래핑 실측 기록 (2026-09-19)

reddit 예제의 KNOWHOW와 같은 형식: 무엇을 시도했고, 무엇이 살았고, 무엇이
죽었는지의 전기록. 이 문서가 CLI의 설계 근거다.

## 1. 소스 라우팅 — 어떤 표면이 살아있나

네이버 카페 검색(`search.naver.com?ssc=tab.cafe.all`)은 **서버사이드
렌더링**이다. view-source에 결과가 그대로 있고, 추가 페이지는 무한스크롤
XHR이 채운다. 브라우저 없이 stdlib HTTP만으로 전부 접근된다.

| 표면 | 상태 | 비고 |
|---|---|---|
| `s.search.naver.com/p/cafe/48/search.naver` (XHR) | ✅ 익명 200 | 무한스크롤이 치는 엔드포인트. JSON 안에 HTML 프래그먼트 |
| `search.naver.com/search.naver` (www SSR) | ✅ 익명 200 | 같은 쿼리 파라미터, 완전 HTML. 폴백용 |
| 네이버 공식 검색 API (openapi) | ❌ 유료/키 | 카페 문서 검색은 비공개 수준 — 키 없이는 불가 |
| 카페 자체 `cafe.naver.com` 스크래핑 | ⚠️ 로그인 장벽 | 개별 카페 글 목록/본문은 대부분 가입 필요. 검색 API로 우회 |

**정직한 UA로 익명 작동 확인.** 쿠키 제거(`credentials:'omit'`)해도
동일 결과. 네이버 검색은 봇벽이 아니라 소프트 레이트리밋으로 방어한다.

## 2. 파라미터 의미론 (엔드포인트 공통, 실측 확정)

카페검색 탭의 옵션 UI가 노출하는 값 그대로:

| 파라미터 | 값 | 의미 (실측) |
|---|---|---|
| `query` | 자유 텍스트 | 검색어. URL-인코딩 |
| `ssc` | `tab.cafe.all` | 카페 탭 고정값. 빠뜨리면 통합검색이 온다 |
| `cafe_where` | `''` | **전체 카페 게시글** (기본값. "모든 카페에서 검색") |
| | `cafe` | **카페명 검색** — 카페 이름 + **카페 설명글** 매칭. 멤버수/랭킹/새글수/전체글수 포함 |
| | `articleg` | 일반글만 |
| | `articlec` | 거래글만 (실측: "완료 그랜드스타렉스 캠핑카" 등 거래성 타이틀) |
| `st` | `rel` / `date` | 관련도순 / 최신순 (실측: date는 "12분 전"부터) |
| `date_option` | 0~7 | 전체/1시간/1일/1주/1개월/3개월/6개월/1년 (www 옵션 HTML에서 추출, 실측 일치) |
| `display` | 무시됨 | 항상 30개 고정. 넣어도 변화 없음 |
| `start` | ⚠️ 조건부 | www에서는 **무시** (항상 1페이지). XHR에서도 브라우저 발급 `nlu_query`가 동반될 때만 실제 페이지네이션 (start=31 → overlap 0 확인). nlu_query는 쿼리 의존 분석 결과라 CLI가 합성 불가 |

응답 포맷: XHR은 `{"result":{"section":[{"html": "..."}]}}` (짧은
파라미터) 또는 `{"collection":[{"html":"..."}]}` (풀 파라미터) — 두
래핑 모두 파서가 처리한다. www는 그냥 HTML.

## 3. 시행착오 기록

### 3단계 프로브 절차 (반복 가능)

1. **CDP 헤드풀로 페이지 구조 확인** — 한국 사이트는 curl보다 실브라우저
   먼저 (규칙). SSR 확인: view-source에 `title_link` 존재.
2. **페이지 내부 `fetch(..., {credentials:'omit'})`** — 익명 접근 가능성
   확인. 이 단계에서 "쿠키 없어도 된다" 확정.
3. **무한스크롤 트리거 + `network requests`** — 진짜 XHR 엔드포인트와
   풀 파라미터 캡처. 이게 엔진 1의 정체.

### 밟은 함정들

- **`agent-browser eval`에 화살표 함수 금지** — `() => ...` 형태는 조용히
  `{}` 반환. 표현식만 쓸 것. (browser-cdp-automation 스킬의 기록된 함정과
  동일. 재확인됨.)
- **eval Promise 반환값 즉시 못 받음** — fetch 결과는 `window.__x`에
  넣고 다음 eval로 회수하는 2단계 패턴 사용.
- **파라미터 절반만 보내면 200 + 빈 body** — `stnm`/`qvt`/`m`/`ac` 등
  브라우저 잔여 파라미터를 "의미 없을 것"이라 임의로 섞으면 오히려 빈
  응답. **최소 동작셋과 풀셋 사이 중간 지점은 위험** — 최소셋으로
  확정하고 필요한 것만 추가한다.
- **`start`가 동작하는 것처럼 보이는 착시** — minimal 셋에 start=31을
  넣으면 overlap 8/30인 "절반만 섞인" 페이지가 온다. 완전 페이지네이션
  (overlap 0)은 nlu_query 동반시만. overlap 비율을 재는 차등 테스트가
  없으면 "작동한다"고 오판한다.
- **`<li class="bx` 분할 파싱** — 게시글/카페명/옵션행이 같은 `li.bx`
  마커를 쓴다. 카페명 행은 `name_area` 마커로, 옵션행은 `user_box`
  부재로 변별.
- **URL 정규화** — 결과 링크에 `?art=<JWT>&q=...` 트래킹이 붙는다.
  `split("?")[0]`로 정리한 clean url을 id로 제공.
- **`display=5`를 요청해도 30개** — 서버가 무시. 클라이언트 `--limit`로
  자른다.

## 4. 레이트리밋 실측

- 연속 호출(수 초 간격 3~4회) → **HTTP 200 + 본문 0바이트**. 429가 아니라
  조용한 빈 응답이므로 "len==0 → Blocked" 감지가 필수.
- 회복: ~8-12초 대기 후 정상.
- 그래서 기본 스로틀 6초/호스트 + 캐시 TTL 300s. `Retry-After` 헤더는
  오지 않으므로 고정 백오프(9s × 3회) 후 www 엔진 전환 → 안 되면 exit 3.

## 5. 재점검 절차

```bash
# XHR 엔진 살아있나
curl -sS -A "ncafe/check" 'https://s.search.naver.com/p/cafe/48/search.naver?query=%EC%BA%A0%ED%95%91&ssc=tab.cafe.all&st=rel&cafe_where=&display=30&start=1&date_option=0' | head -c 120
# www 폴백 살아있나
curl -sS -A "ncafe/check" 'https://search.naver.com/search.naver?ssc=tab.cafe.all&query=%EC%BA%A0%ED%95%91' -o /dev/null -w '%{http_code}\n'
# 전체 검증
./smoke-test.sh
```

## 6. 알려진 한계 (숨기지 않는다)

- **한 번의 호출 = 한 페이지(약 30개)**. nlu_query 없이는 start 페이지네이션이
  불가. 필요하면 쿼리를 구체화하거나 `--date`로 좁힌다.
- 개별 카페 **내부** 검색(특정 카페 안에서만)은 미구현 — 그 표면은
  가입/인증이 필요한 `cafe.naver.com` 내부라 익명 래핑이 아님.
- 게시글 **본문 전체**는 미제공 — 검색 스니펫(300자)까지만. 본문 크롤링은
  로그인 장벽 + 카페별 정책 문제라 범위 밖.
- 카페 설명(`cafes`)의 `rank_tier`는 네이버 등급 체계 변경시 깨질 수 있는
  자유 텍스트.
