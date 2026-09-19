# dc — 익명 DC Inside 갤러리 리더 CLI

계정 없이, 쿠키 없이, Python 3 표준 라이브러리만으로 디시인사이드 갤러리를
읽는다. any2cli 컨트랙트 준수.

## 사용

```bash
dc posts programming                    # 갤러리 리스트 (공지 제거, 글번호·제목·닉·IP·조회·추천·댓글수)
dc posts programming --page 2           # 페이지네이션 (실측 작동)
dc posts minor:ai --limit 10            # 마이너 갤러리
dc search programming 파이썬            # 갤 내 검색 (제목)
dc search programming 파이썬 --field all  # 제목+내용+닉
dc post programming 2939751             # 본문 + 댓글 트리 (대댓글 depth 포함)
dc post programming 2939751 --comments 100
```

출력 레코드 (json):
- post(list): `{num, title, url, nick, uid, ip, date, views, recommends, comments, has_img}`
- detail: `+ {body_text, images, gallery}` 와 `comments: [{no, nick, ip, date, memo, rcnt, depth, deleted}]`

## 엔진

| 엔진 | 소스 | 특징 |
|---|---|---|
| ssr-list | `board/lists` / `mgallery/board/lists` SSR | 정직한 도구 UA, 쿠키 0 |
| ssr-view+comment-json | `board/view` SSR + `POST board/comment/` JSON | 댓글은 comment.js 폼 재현 (KNOWHOW §2) |

주의: **HTTP 표면에서는 모바일 UA가 차단된다** (CDP 브라우저 규칙과 반대).
스로틀 4s/호스트, 캐시 300s, 404=exit 4.

## 상태

- smoke-test 9/9 통과 (2026-09-19 실호출: 리스트/페이지네이션/검색/상세/댓글/마이너갤/exit코드)
- 한계: 미니갤(멤버제), 전 갤러리 통합검색(다음 프록시 부정확), 조회순 정렬(파라미터 무시됨)
- 역공학 전기록: [KNOWHOW.md](KNOWHOW.md)
