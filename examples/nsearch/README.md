# nsearch — 익명 네이버 뉴스+블로그 검색 CLI

계정·쿠키 없이, Python 3 stdlib만으로. any2cli 컨트랙트 준수.

## 사용

```bash
nsearch news 인공지능                    # 뉴스 검색 (관련도순)
nsearch news 인공지능 --sort recent      # 최신순
nsearch news 인공지능 --days 7           # 최근 1주
nsearch news 인공지능 --start 11         # 다음 페이지 (~10개/페이지, 실측 작동)
nsearch blogs 캠핑텐트                    # 블로그 포스트 (상위 카드들)
```

출력 레코드 (json):
- news: `{title, url(원문), naver_url(n.news), press, date, snippet}`
- blog: `{title, url(blog.naver.com), blogger, date, snippet?, kind}`

## 엔진

| 엔진 | 소스 | 특징 |
|---|---|---|
| news-more-json | `s.search.naver.com/p/newssearch/3/api/tab/more` XHR | start 페이지네이션 작동, sort·pd 필터. 일시적 null collection은 캐시 오염 방지 |
| blog-www-ssr+ader-resolve | www SSR + ader 리다이렉트 해석 | 3종 카드 형태 파싱 (fender-ui) |

2026년 네이버 검색은 fender-ui 컴포넌트로 마이그레이션 — 구 `news_tit` 선택자는
작동하지 않고 `data-heatmap-target=".tit"` 등 속성 마커로 파싱한다 (KNOWHOW §3).

## 상태

- smoke-test 9/9 통과 (2026-09-19 실호출)
- 한계: 블로그는 익명 상위 카드(~5-8개)만 — 더보기에 로그인 필요. 뉴스 매체필터 미검증.
- 실측 기록: [KNOWHOW.md](KNOWHOW.md)
