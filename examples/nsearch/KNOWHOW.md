# nsearch CLI 노하우 — 네이버 뉴스+블로그 검색 래핑 실측 기록 (2026-09-19)

## 1. 무엇이 살아있나

| 표면 | 상태 | 비고 |
|---|---|---|
| `s.search.naver.com/p/newssearch/3/api/tab/more` | ✅ 익명 200 | 뉴스탭 무한스크롤 XHR. `{"collection":[{"html":...}]}` — **ncafe의 ssearch와 같은 계열** |
| `search.naver.com?ssc=tab.blog` www SSR | ✅ 익명 200 | 블로그 카드 포함. 단 **고유 블로그 포스트 ~5-8개**뿐 (더보기는 비로그인 불가) |
| `search.naver.com?where=news` www SSR | ⚠️ 결과 대부분 없음 | SSR 셸 + 옵션 UI만. 결과는 tab/more XHR이 담당 |
| `section.blog.naver.com/Search/Post.naver` | ❌ 셸만 | 37KB, 결과 없음 |
| `ader.naver.com/v1/...` | ✅ 리다이렉트만으로 해석 | 블로그 카드의 추적 링크 → `Location` 헤더로 실제 blog.naver.com URL 회수 (본문 fetch 불필요) |

## 2. 뉴스 XHR 파라미터 (실측 확정)

| 파라미터 | 값 | 의미 |
|---|---|---|
| `query` | 검색어 | |
| `start` | 1, 11, 21… | **완전 작동** (약 10개/페이지). www의 start가 무시되는 것과 대조적 |
| `sort` | 0 / 1 | 관련도순 / 최신순 (실측: sort=1 → "1분 전" 연속) |
| `pd` | -1 / N | 전체 / N일 기간필터 (pd=7 → 최근 일주일) |
| `ssc` | `tab.news.all` | 고정 |
| `photo`, `field`, `mynews`, `rev` | 0 | 형식 필터 (미검증 상세) |
| `nso` | 무시됨 | minimal 셋에서는 nso 값 무관하게 동일 응답 — pd가 실제 기간 스위치 |

**주의: 일시적 null collection** — 같은 파라미터로偶尔 `{"collection": null}` 이 온다.
이 응답을 캐시에 저장하면 이후 같은 쿼리가 캐시 TTL 동안 계속 빈 결과로 죽는다
(실제로 발생해서 smoke-test가 잡음). → null collection은 캐시 무효화 + Blocked 처리.

## 3. fender-ui 파싱 (2026 뉴스/블로그탭 신규 컴포넌트)

구버전 `news_tit`/`api_txt_lines` 선택자는 **전부 죽었다**. 현재 구조:

- 제목 앵커: `data-heatmap-target=".tit"` — 난독화 CSS 클래스(`fender-ui_a82de4df`)와
  무관하게 이 속성이 안정적 마커.
- 매체명: `alt="<매체명>의 프로필 이미지"` (Profile 썸네일 img의 alt).
- 시간: 카드 텍스트 체인에서 `N시간/일 전` 또는 `2026.09.18.`
- 제목에 `<mark>` 하이라이트가 인라인 태그로 끼어든다 → 태그 제거 후 제목 조각 join 필요.
- **블로그 카드는 3종**:
  1. `.tit` + ader.naver.com href → 리다이렉트 해석으로 실 URL
  2. `.simg` (썸네일) + 직접 blog URL + 제목이 `img alt="...의 이미지"`
  3. `.link` (공식블로그 프로필형) → 제목이 앵커 **내부** 텍스트에 있거나(SVG 노이즈면)
     카드 뒤쪽 img alt에 — 규칙: 노이즈면 뒤 5000자에서 alt 제목 회수
- alt 속성값 안의 `&lt;mark&gt;` 엔티티: unescape → 재태그제거 2패스 필수.

## 4. 블로그 페이지네이션 — 익명 불가 (확정)

- www blog 탭: 고유 포스트 ~5개 (SSR), 스크롤/더보기 클릭으로 증가 없음.
- 브라우저 DOM도 동일 5개 (JS 하이드레이션 없음 — 아까 "25 blog links"는
  서브링크/미리보기 중복이었다).
- `qra/1/search.naver` (통합탭 more)는 `enc_pageid` 세션 토큰 필요 — 익명 폼 재현 불가.
- 결론: `blogs` 명령은 "상위 카드"로 문서화. 깊은 블로그 검색은 naver 로그인 세션 필요.

## 5. 재점검 절차

```bash
# news XHR
curl -sS -A "nsearch/check" 'https://s.search.naver.com/p/newssearch/3/api/tab/more?query=test&start=1&sort=0&ssc=tab.news.all&pd=-1' | head -c 150
# blog www
curl -sS -A "nsearch/check" -o /dev/null -w '%{http_code}\n' 'https://search.naver.com/search.naver?ssc=tab.blog&query=test'
./smoke-test.sh
```

## 6. 알려진 한계

- 뉴스 기간필터는 pd(일 단위)만; nso 세부(so:pp 등)는 minimal 셋에서 무시됨.
- 블로그 1페이지 상위 카드만 (익명 제약, §4).
- 뉴스 매체 필터(mynews/office) 미검증.
- 관련기사 클러스터尾部 카드는 press/date 필드가 없는 경우가 있음 (정상).
