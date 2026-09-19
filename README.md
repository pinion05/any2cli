# any2cli

모든 데이터 소스를 CLI로 래핑하는 방법론 스킬 + 익명 Reddit CLI 예제.

- **웹사이트** → headless Playwright으로 렌더링해서 CLI로
- **웹 API** (공식/비공식/RSS/아카이브) → 멀티엔진 폴백 CLI로
- **데스크톱 앱** → AppleScript/CDP/상태파일로 CLI로

AI 에이전트(Claude Code / ZCode 등)용 스킬이자, 사람이 쓰는 방법론 문서입니다. "X를 CLI로 만들어줘"라는 모든 요청에 적용됩니다.

## 설치 (에이전트 스킬로)

```bash
git clone https://github.com/pinion05/any2cli ~/.agents/skills/any2cli
```

그러면 "CLI로 만들어줘 / 래핑해줘 / 이 사이트·API·앱을 셸에서 읽고 싶어"류 요청에 스킬이 자동 발동합니다. 핵심 문서:

- [SKILL.md](SKILL.md) — 워크플로우: 분류 → 실측 프로브 → 설계 → 구현 → 검증
- [references/](references/) — CLI 컨트랙트, API 래핑, Playwright 래핑, 데스크톱 래핑

## 대표 예제: 익명 Reddit CLI

[examples/reddit/](examples/reddit/) — 계정 없이, API 키 없이, 레딧을 셸에서 읽는 도구. 이 저장소의 방법론이 전부 적용된 실증 구현체입니다.

```bash
reddit posts r/python --sort top --time week   # 게시글 목록 + upvote
reddit search "rust vs go" --sort top --time month
reddit search asyncio --sub python             # 서브레딧 내 검색
reddit subs "machine learning"                 # 서브레딧 검색
reddit post 1wi6dpv                            # 상세: 점수·비율·본문
reddit comments 1wi6dpv --sort top             # 댓글 트리 + 점수
reddit user spez                               # 유저 활동
```

4개 엔진 자동 폴백 (2026-09 전부 실측 검증):

| 엔진 | 소스 | 특징 |
|---|---|---|
| oauth (옵트인) | app-only 토큰 (계정 불필요) | live 점수 + upvote_ratio, 1000요청/10분 |
| redlib | 커뮤니티 미러 | live 점수, 검색·댓글 정렬 |
| rss | www.reddit.com Atom | 1자당 신선, `after=` 페이지네이션 |
| arctic + pullpush | 커뮤니티 아카이브 | id 조회·댓글 트리·과거 데이터 |

```bash
# 소스 직접 (Python 3.8+ stdlib만, 의존성 0)
~/.agents/skills/any2cli/examples/reddit/reddit posts r/python

# 단일 바이너리로 빌드 (3.8MB, Python 불필요)
cd ~/.agents/skills/any2cli/examples/reddit && ./build.sh --install
reddit posts r/python
```

**[examples/reddit/KNOWHOW.md](examples/reddit/KNOWHOW.md)를 먼저 읽으세요** — 뭐가 차단됐고, 뭐가 살아남았고, HTML 파싱 함정은 뭔지, 기존 오픈소스는 왜 전멸했는지의 전기록입니다. 잠긴 사이트를 래핑하는 절차 자체가 이 문서의 본체입니다.

## 상태

- smoke-test 17/17 통과 (전 서브커맨드 실호출: exit code·JSON·캐시·subreddit==permalink 정합성)
- 기존 오픈소스 지형 조사 완료: 익명 멀티엔진 조합은 이 저장소가 유일 (KNOWHOW §4)
