# dc CLI 노하우 — DC Inside 래핑 실측 기록 (2026-09-19)

reddit/ncafe와 같은 형식의 전기록. 이 문서가 CLI 설계의 근거다.

## 1. 무엇이 살아있나 (엔진 발견 순서)

| 표면 | 상태 | 비고 |
|---|---|---|
| `gall.dcinside.com/board/lists/?id=` (메인갤 SSR) | ✅ 익명 200 | **정직한 도구 UA**로 행 49개 SSR. 쿠키 0 |
| `gall.dcinside.com/mgallery/board/lists/?id=` (마이너갤) | ✅ 익명 200 | 동일 파서. 존재하지 않는 마이너갤 id는 board/lists로 JS 리다이렉트 — CLI가 이를 따라감 |
| `gall.dcinside.com/board/view/?id=&no=` (상세 SSR) | ✅ 익명 200 | 제목/본문/이미지/작성자 SSR |
| `POST gall.dcinside.com/board/comment/` (댓글 JSON) | ✅ 익명 200 | **본문 참조: `{"total_cnt", "comments":[{no,name,ip,reg_date,memo,rcnt,depth,...}]}`** |
| `gall.dcinside.com/mini/board/lists/` (미니갤) | ⚠️ 대부분 멤버 전용 | `programming` 미니갤은 비공개 — 빈 리스트는 차단이 아니라 비공개 갤일 수 있음 |
| 통합검색 `search.dcinside.com` | ❌ | 다음(Daum) 프록시 — 스킬 기록 재확인. 갤 내 검색으로 대체 |
| 모바일 UA (`Mozilla/5.0 (Linux; Android...)`) | ❌ 75바이트 차단 | **HTTP 표면에선 역전**: 브라우저(CDP)에선 모바일 UA 필요, 순수 HTTP에선 정직 UA 통과 |

## 2. 댓글 POST 역공학 (이 예제의 하이라이트)

댓글은 SSR에 없고 `comment.js`의 `$.ajax` POST로 로드된다. 재현 경로:

1. **view HTML에서 토큰 추출**: `e_s_n_o` (hidden input).
2. **comment.js 소스를 읽고 필드셋 확보**:
   `id, no, cmt_id, cmt_no, focus_cno, focus_pno, e_s_n_o, comment_page, sort, prevCnt, board_type, _GALLTYPE_, secret_article_key, clean, nptest`
3. **첫 재현은 "정상적인 접근이 아닙니다"** — 실패한 이유는 필드값:
   - `cmt_id`/`cmt_no`는 **빈 값이 아니라** 갤 id와 글 번호 그대로
   - `sort=D`, `prevCnt=` (빈), `board_type=` (빈)
   - `service_code` 폼/쿠키는 **불필요** (넣어도 소용없고 안 넣어도 됨)
4. **실측 폼 캡처 방법**: agent-browser의 HAR 미지원 → **CDP websocket 직접 연결**로
   `Network.requestWillBeSent`의 `postData` 캡처 (Page.reload 트리거 후 12초 윈도우).
   브라우저 $.ajax 몽키패치는 로드 직후 요청이라 패치 전에 끝나 못 잡음.
5. **e_s_n_o는 세션 불문 공유 토큰**: 쿠키 0인 새 프로세스에서 같은 값으로 POST 성공.
   → CLI는 view HTML에서 매번 추출하되 쿠키jar 불필요.

## 3. 파라미터 의미론 (실측 확정)

| 파라미터 | 값 | 의미 |
|---|---|---|
| `id` | 갤 id | programming 등. 마이너갤은 URL prefix로 구분 |
| `page` | 1..N | **완전 작동** — page1/page2 글번호 완전 분리 확인 |
| `s_type` | `search_subject` / `search_all` / `search_name` / `search_memo` | 제목 / 전체 / 닉 / 내용 |
| `s_keyword` | 검색어 | **`search_keyword`가 아니라 `s_keyword`** — 폼 hidden input에서 확보 |
| 댓글 `comment_page` | 1..N | 50개+ 단위 페이지네이션 |
| 댓글 `sort` | `D` | 등록순 기본값 |

무시되는 것: `sort_hit` (조회순/추천순 파라미터는 응답不变 — 클라이언트 정렬 필요).

## 4. 차단·회피 관찰

- 모바일 UA → 75~183 바이트 + JS 리다이렉트. **UA 하나로 생사가 갈림.**
- 연속 호출에 대한 소프트 차단은 관찰 안 됨 (4s 스로틀로 예방).
- 404 = 갤 id 없음 → exit 4.
- 미니갤 비공개 = 빈 SSR (차단 아님) — `document.title`에 "비공개" 렌더.

## 5. 재점검 절차

```bash
# 메인갤 SSR 살아있나
curl -sS -A "dc-cli/check" 'https://gall.dcinside.com/board/lists/?id=programming' -o /dev/null -w '%{http_code}\n'
# 댓글 POST 폼이 아직 유효한지 (view에서 e_s_n_o 추출 후)
./smoke-test.sh
```

## 6. 알려진 한계

- 미니갤(mini)은 멤버 전용이 많아 지원 안 함 (mgallery까지만).
- 통합검색(전 갤러리 횡단 검색)은 다음 프록시라 부정확 — 갤 내 검색만 제공.
- 조회순/추천순 정렬 파라미터 무시됨 — 필요시 클라이언트 정렬.
- 댓글 `sort=D` 등록순 고정 (인기순 미검증).
