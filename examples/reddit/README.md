# reddit — 익명 읽기 전용 Reddit CLI (any2cli 예제)

계정 없이, API 키 없이, 셸에서 레딧을 읽는다. `any2cli` 스킬의 대표
작동 예제. **이 예제의 본체는 [KNOWHOW.md](KNOWHOW.md)다** — 무엇을
시도했고 어떻게 실패했으며 무엇으로 살아남았는지의 전기록. 코드는 그
노하우의 실증 구현체다. Python 3.8+ 표준 라이브러리만 사용 (의존성 0).

```bash
R=~/.agents/skills/any2cli/examples/reddit/reddit

$R posts r/python --sort top --time week --limit 10  # 목록 + live upvote
$R search "rust vs go" --sort top --time month       # 전체 게시글 검색
$R search asyncio --sub python                       # 서브레딧 내 검색
$R subs "machine learning"                           # 서브레딧 검색
$R post 1wi6dpv                                      # 상세(upvote/댓글수)
$R comments 1wi6dpv --limit 50 --sort top            # 댓글 트리 + 점수
$R user spez                                         # 유저 게시글
$R user spez --kind comments                         # 유저 댓글
$R posts r/python --engine rss                       # 엔진 강제 지정
```

사용(스크립트 직접): `~/.agents/skills/any2cli/examples/reddit/reddit ...`
또는 단일 바이너리: `reddit ...` (아래 빌드 참조)
검증: `./smoke-test.sh` (전 서브커맨드 실호출, exit code·JSON·캐시 점검)

## 단일 바이너리 빌드 (Python 불필요한 독립 실행파일)

```bash
cd ~/.agents/skills/any2cli/examples/reddit
./build.sh --install        # dist/reddit 빌드 + ~/.local/bin/reddit 설치
```

- stdlib-only 소스를 PyInstaller로 프리징 — **Python 없는 머신에서도
  동작** (`env -i` 무환경 실행 확인). macOS arm64 기준 **3.8MB**.
- 빌드는 격리 venv에서 (사용자 site-packages 오염 없음), 대상 플랫폼에서
  각각 빌드 (바이너리는 OS/arch 종속).
- onefile 특성상 첫 실행에 ~1-4초 압축 해제 오버헤드. 잦은 호출이면
  스크립트(`./reddit`) 직접 실행이 더 빠름 — 바이너리는 배포용.
- 캐시/스로틀은 그대로 `~/.cache/any2cli/reddit/` 공유.

## 엔진 4종 + 자동 폴백

| 엔진 | 소스 | 강점 | 약점 |
|---|---|---|---|
| `oauth` (설정 시 최우선) | oauth.reddit.com — app-only 토큰 (계정 불필요, `ANY2CLI_REDDIT_CLIENT_ID` [+`..._SECRET`] 설정 시 활성) | **live score + upvote_ratio + 댓글수**, limit=100, after= 페이지네이션, 1000요청/10분 | 타 앱 id 사용 시 버킷 공유·폐기 리스크 (KNOWHOW §6) |
| `redlib` (기본) | 커뮤니티 미러(기본 `redlib.ducks.party`, `ANY2CLI_REDLIB_URLS`로 교체) | **live 점수**, 검색·댓글 정렬·유저 페이지, 레이트리밋 관측 없음 | 봉사자 인스턴스라 언제 죽을지 모름, ratio 미제공 |
| `rss` | www.reddit.com Atom 피드 | 1자당 신선, `after=`/`type=sr`/`t=` 지원 | 점수 없음 + 창당 ~1요청 레이트리밋 → arctic이 점수 보강 |
| `arctic` (+pullpush) | arctic-shift 아카이브 API (+pullpush ids 조회) | id 정밀 조회·댓글 트리·유저 히스토리·키워드 폴백 | 점수는 수집 시점 스냅샷 |

기본 동작(`--engine auto`): env에 client id가 있으면 oauth → 아니면
`redlib → rss(+arctic 점수보강) → arctic` 자동 전환. 전환은 stderr +
결과 `engine` 필드로 표시. 필드 단위 근사치는 `score_source`(예:
`"oauth(live)"` vs `"arctic-archive"`)로 구분.

## 근사치(제약) 명시

- oauth 엔진 = 완전 라이브(점수·비율·댓글수 전부). redlib = 라이브
  점수(비율 미제공). arctic/rss 경유 시 점수는 수집 시점 값.
- rss 엔진 경유 시 429 대기(기본 8초/호스트 스로틀) 발생. 지속 시 exit 3.
- hot 정렬은 라이브(oauth/redlib/rss). arctic 단독 폴백 시 시간 역순 대체.
- 서브레딧 검색(`subs`): oauth(구독자수 포함) → rss. redlib엔 그 기능 없음.
- 환경변수: `ANY2CLI_REDDIT_CLIENT_ID`(+`..._SECRET`) oauth 활성화,
  `ANY2CLI_REDLIB_URLS` 미러 목록 교체.

## 컨트랙트 요약

- TTY면 테이블, 파이프면 JSON. `--format table|json|jsonl|md`.
- exit code: 0 성공 · 2 사용법 · 3 레이트리밋/차단 · 4 없음 · 1 기타.
- 캐시 `~/.cache/any2cli/reddit/` (TTL 300초, `--fresh` 무시, `-v`로 확인).
- 모든 레코드에 id + permalink → 출력이 다음 커맨드 입력으로 체이닝됨.

## 파일

- `reddit` — 실행 파일 전체 (단일 파일, stdlib만)
- `build.sh` — 단일 바이너리 빌드 스크립트 (PyInstaller, 격리 venv)
- `dist/reddit` — 빌드된 독립 바이너리 (macOS arm64, 3.8MB)
- `KNOWHOW.md` — **시행착오 전기록 + 파싱 함정 + 재점검 절차** (예제의 본체)
- `smoke-test.sh` — 실호출 검증 스크립트

2026-09-18 실측: 전 서브커맨드 실데이터 반환 확인 (r/python hot live
점수, "Flet 1.0" score 236/234 드리프트, spez "21 years of Reddit"
아카이브 606 vs live 896 등 — KNOWHOW.md 참조).
