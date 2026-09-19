# reddit CLI 노하우 — 시행착오 전체 기록 (2026-09-18 실측)

이 문서가 예제의 본체다. 코드(`reddit`)는 아래 노하우의 실증 구현체일
뿐이다. **같은 방법으로 다른 사이트를 래핑할 때 이 문서가 절차의
템플릿**이다: 문서/관습을 믿지 말고 → 하나씩 찔러보고 → 실패를 기록하고
→ 그 흔적 위에 엔진을 설계한다.

---

## 1. 시행착오 타임라인 (무엇을 시도했고 어떻게 죽었나)

### 1단계: "공식" 경로 — 전부 차단

| 시도 | 결과 | 교훈 |
|---|---|---|
| `www.reddit.com/r/python/hot.json` + 정직한 UA | **403** (block 페이지) | 로그아웃 .json은 UA 무관 차단 |
| 같은 URL + 실제 Chrome UA + `Accept: application/json` | **403** | UA 위장 소용 없음. IP/정책 기반 |
| `api.reddit.com/r/python/hot` | **403** | api.* 하위도 같은 정책 |
| `old.reddit.com/...json` | **302 → 로그인** (`reason=lor2`) | "로그인해라" 리다이렉트 |
| `old.reddit.com` HTML + edgebucket 쿠키 | 200이지만 "Welcome to Reddit" 껍데기 (게시글 0개) | 쿠키로 안 풀림 |

### 2단계: 브라우저 — 여기서도 죽음

| 시도 | 결과 | 교훈 |
|---|---|---|
| playwright headless chromium (시스템 Chrome channel) | **"You've been blocked by network security"** + `js_challenge=1` 리다이렉트 | headless 지문 차단 |
| headful Chrome + `navigator.webdriver` 제거 + `--disable-blink-features=AutomationControlled` | **동일 차단**, 30초 대기해도 챌린지 미해제 | IP 평판 기반. 싸우지 마라 |
| 브라우저 연결 후 **페이지 내부에서** `fetch('/r/python/hot.json')` | **403** (same-origin여도) | 쿠키/지문이 아니라 정책임을 확정 |

**핵심 교훈: 차단당한 경로와 싸우지 말고, 살아있는 표면을 찾아라.**
"웹사이트는 playwright로"가 아니라 "playwright는 최후의 수단"이라는 게
이 사례의 결론. (any2cli 스킬의 decision ladder가 이 경험에서 나왔다.)

### 3단계: RSS — 살아있는데 빡빡함

| 시도 | 결과 |
|---|---|
| `www.reddit.com/r/python/hot.rss` | ✅ 200 (기본 25개) |
| 연속 호출 (search.rss, comments.rss, subreddits/search.rss) | **429 다수** — 몇 초 안에 몇 번만 쳐도 |
| 20~30초 쿨다운 후 재시도 | 대부분 회복 → **Retry-After 존중 + 스로틀 필수** |
| `comments.rss` URL 형식 | `/r/<sub>/comments/<id>.rss` ✅, bare `/comments/<id>.rss` ✅ (단, 짧은 UA `-A "Mozilla/5.0"` 만 쓰면 403 — **풀 브라우저 UA 필요**) |
| `/subreddits/search.rss?q=` | 들쑥날쑥 (어떤 날 200, 어떤 날 429 지속) → 폴백 필요 |
| `search.rss?q=` | 결과에 **게시글(t3_)과 서브레딧(t5_) 카드가 섞여** 옴 → 엔트리 `<id>` 접두사로 변별 |

개발 중 사고: `grep -c "<entry>"`로 개수를 세니 XML이 **한 줄**이라
항상 1이 나옴. `grep -o ... | wc -l`로 바꿔야 했다. (측정 도구가
거짓말하면 결론도 거짓말한다.) 또 하나: `lstrip("r/")`로
`"r/retroid"`에서 접두사를 뺐더니 **"etroid"**가 됐다 — lstrip은 접두사
문자열이 아니라 **문자셋**을 받아 'r','/','r'을 연달아 제거함. 접두사
제거는 `re.sub(r"^r/", "", s)`. 이 버그는 smoke-test를 16/16 통과하고도
살아있었다 — "있는 필드가 찍힌다"가 아니라 "**값이 참인지**"를 검사하는
항목(subreddit==permalink)이 없으면 못 잡는다.

차등 테스트로 확정한 **RSS 파라미터 의미론** (엔트리 id diff로 검증):

| 파라미터 | 동작 | 비고 |
|---|---|---|
| `?after=t3_xxx` | ✅ **완전 페이지네이션** | 다음 페이지가 정확히 이어짐 (첫 엔트리 = 이전 페이지 [3]번) |
| `?limit=50` | ✅ | 목록은 50개 그대로 반환 |
| `?t=day\|week\|...` | ✅ | top/controversial 창 (day 결과 ⊂ week 결과 확인) |
| `?type=sr` / `?type=link` | ✅ | 검색 결과를 서브레딧/게시글로 분리 — 서브검색 폴백의 정석 |
| `?sort=top` (댓글 피드) | ✅ | 순서 실제로 바뀜 |
| 댓글 피드 `limit` | ⚠️ 부분 | 파싱은 하지만 **피드당 ~70개 상한**, 선형 매핑 안 됨 |

**익명 www 레이트리밋의 실체**: 응답 헤더 `x-ratelimit-used: 1 /
remaining: 0.0` — 버킷이 **창당 ~1요청**. 지속적으로 분당 1회 이상 치면
빈 몸통의 429가 즉시 옴 (Retry-After 없음). 그래서 이 CLI의 rss 기본
스로틀은 8초/호스트 + 캐시 + 자동 엔진 전환.

### 4단계: 아카이브 API — 점수의 실마리

Arctic Shift (`arctic-shift.photon-reddit.com/api`) — Pushshift 후계
커뮤니티 아카이브. **계정/키 불필요.**

| 파라미터 실험 | 결과 |
|---|---|
| `/posts/ids?ids=t3_x` | ✅ score·upvote_ratio·num_comments·selftext 완전 제공 |
| `/posts/search?subreddit=&sort=desc&limit=` | ✅ 시간 역순 목록 |
| `&q=` (키워드) | ❌ 400 `Unknown query parameter` — **q는 없음** |
| `&title=` | ⚠️ 200은 나오지만 서버 풀스캔이라 **422 Timeout 자주** ("Maybe slow down a bit") |
| `&author=`, `&after=`/`&before=` | ✅ |
| `/comments/search?link_id=` | ✅ parent_id 포함 → 트리 재구성 가능 |

값의 성격: **수집 시점 스냅샷.** 실측 비교 — "21 years of Reddit":
아카이브 score 606 / 실시간 896. 댓글수 19 / 103. 즉 아카이브는
"근사치"지 실시간이 아님 → `score_source` 마커로 항상 구분하게 설계.

pullpush.io (2번째 아카이브):
- `/submission/?ids=` ✅, `/comment/?link_id=` ✅ — **수집 지연 ~15초** (거의 실시간, 신규 글에 강함)
- `subreddit=`/`q=`/`author=` 검색 → **429 "does not provide free scraping
  resources for agents"** — UA·쿨다운·다른 IP 무관한 **엔드포인트 단위
  안티에이전트 정책.** 검색 용도로는 죽은 샘이지만 ids 조회용으로 살림.

### 5단계: 미러 (redlib) — 실시간 점수의 해답

redlib(libreddit 후계) 공개 인스턴스 25개+ 테스트 결과:
- **전멸**: Anubis/Cloudflare/자체 봇벽(safereddit "Verifying your
  browser", artemislena "Making sure you're not a bot", nadeko 418,
  catsarch는 reddit 업스트림 차단 429 "Oh noes!" …), 죽은 DNS 다수.
- **생존 1개**: `redlib.ducks.party` — 봇벽 없음, 쿠키 불필요,
  관측된 레이트리밋 없음, **live score** (같은 글을 몇 분 간격으로
  조회하면 점수가 22→21→234로 드리프트 = 실시간 확인).

미러는 언제 죽을지 모르니: 인스턴스 목록은 환경변수
(`ANY2CLI_REDLIB_URLS`)로 교체 가능하게, 봇벽 페이지는 HTTP 200이어도
`<title>` 마커("not a bot", "Oh noes", "Just a moment"…)로 검출해서
다음 인스턴스로 넘어가게. **HTTP 상태코드만 믿지 말 것.**

### 부록: 그 외 확인된 것들

- `www.reddit.com/oembed?url=<permalink>` ✅ — 제목/작성자만. **redd.it
  단축 URL은 400 거부** (풀 permalink만 받음) → URL 입력일 때만 최종 폴백.
- `redd.it/<id>` → 301 `Location: /comments/<id>` (id→permalink 해석용).
- `/by_id/t3_x.rss` → 그 순간 429 (동작 확정 못함, 신뢰하지 않음).
- `gateway.reddit.com/desktop-api/v1/...` → www로 301. www의
  desktop-api는 **200을 주지만 함정** — content-type이 text/html이고
  본문은 SPA 셸. JSON 아님 (JS 챌린지 뒤에 있음).
- `api/info.json` + Accept/Accept-Encoding 변형 → 전부 403 (헤더 협상
  문제가 아니라 정책).
- Wayback CDX(`web.archive.org/cdx/search/cdx`) ✅ — 과거 스냅샷 열람용.
  커버리지 희소. reveddit API는 익명 빈 응답. r.jina.ai는 reddit이
  막은 페이지를 그대로 전달(무용).

### 6단계(전화위복): OAuth app-only 토큰 — 익명으로 풀 API

계정 없이 **앱 신원만으로** 발급되는 토큰 그랜트가 아직 살아있다.
검증된 두 흐름:

1. **installed_client** (공개 앱): 공개 OSS가 배포하는 client_id +
   빈 secret. gallery-dl이 배포하는 id(`6N9uN0krSDE-ig`, Basic auth
   `id:`)가 실측 작동:
   ```
   grant_type=https://oauth.reddit.com/grants/installed_client&device_id=<UUID>
   → 200 access_token, scope *, expires_in 86400
   GET oauth.reddit.com/r/python/hot?limit=2 → 200 (score/upvote_ratio/num_comments)
   ```
2. **client_credentials** (기밀 앱): BDFR가 배포한 id+secret 쌍도
   실측 작동.

얻는 것: **oauth.reddit.com 전체 JSON API** — 라이브 score +
upvote_ratio(다른 엔진엔 없음!) + num_comments, limit=100, after= 깊은
페이지네이션, 검색, 댓글 트리 — 버킷 **1000요청/10분** (익명 www의
분당 1회 대비 ~1000배).

시행착오 (여기서도 밟았다):
- `device_id=any2cli-device` → **`bad device_id` 거부**. 형식 검증이
  있음 — **UUID만 받는다** (에이전트가 쓴 `DO_NOT_TRACK_THIS_DEVICE`도
  통과하는 걸 보면 문자셋 제한으로 추정). 기기별 UUID를 캐시해 고정
  사용하는 게 정석.
- oauth Listing 응답은 **`{data: {children: []}}` 이중 래핑**.
  `data.children`에서 꺼내려다 빈 목록을 조용히 리턴하는 버그를
  만들었다 — "성공했는데 0개"는 언랩 버그를 의심하라.

경계 (반드시 함께 문서화할 것):
- 이 id들은 **다른 프로젝트의 것** — 버킷을 공유함 (실측 당시에도
  317/1000 선소진). Reddit이 언제 폐기해도 이상하지 않음 (bdfrx는
  이 때문에 자체 id를 뺐다). ToS 리스크는 사용자 몫.
- 그래서 CLI는 **env 옵트인 방식**만 지원 (`ANY2CLI_REDDIT_CLIENT_ID`,
  선택적 `..._SECRET`). 서드파티 id를 코드에 박지 않는다. 검증 사실은
  이 문서가 기록한다. 토큰은 24h 캐시(`expires_in` 그대로).

---

## 2. redlib HTML 파싱 함정 (실제로 밟은 것들)

v0.36.0 기준. 구버전 문서의 `<article class="post">`는 **없음** —
`div.post`다. 문서가 아니라 실측 HTML을 봐야 하는 이유.

1. **`h2.post_title` 안에 앵커가 두 개**다: flair 앵커(`a.post_flair`,
   예: "News")가 타이틀 앵커보다 **앞에** 온다. "첫 번째 a"를 잡으면
   타이틀이 "News"가 된다 → `post_flair` 클래스를 제외한 앵커를 잡고,
   flair는 별도 필드로. 스레드 페이지(`h1.post_title`)도 동일하게 flair가
   섞여 들어감.
2. **숫자는 전부 `title` 속성에** 있다: `div.post_score[title="234"]`,
   `p.comment_score[title="6"]`, `a.post_comments[title="103 comments"]`,
   `span.created[title="Sep 04 2026, 16:05:19 UTC"]`. 텍스트 노드는
   공백/`<span>` 노이즈가 섞여 있어 파싱 지옥. **속성 우선.**
3. **정렬은 path 형식만 동작**: `/r/python/top?t=week` ✅.
   `?sort=top&t=week`는 **t를 조용히 무시**한다 (응답에 링크는 남아서
   속는다). 차등 테스트(같은 sort에 t만 바꿔 엔트리 id 비교)로 확인.
4. **댓글 id는 `p` 접두사**: `div.comment id="p7tzztd"` → 실제 id는
   `7tzztd` (t1_7tzztd). permalink에도 `p` 붙어있다.
5. **트리 구조**: 자식 댓글은 부모 `div.comment` **내부**의
   `blockquote.replies` 안에 중첩. 부모의 score/author/body를 뽑을 때
   `exclude_cls={"replies"}`로 하위 서브트리를 차단하지 않으면 자식
   댓글의 score를 부모 것으로 오독한다. depth는 조상 중 replies 개수,
   parent는 가장 가까운 조상 div.comment의 id.
6. **유저 페이지 댓글 div에는 id가 없다** (`div.comment.user-comment`).
   id·서브레딧·link_id는 전부 `a.comment_link`의 href
   (`/r/<sub>/comments/<postid>/<slug>/<cid>/`)에서 정규식으로 회수.
7. **스레드 페이지 OP div에는 id 속성이 없음** → post id는 호출자가
   이미 알고 있는 pid로 채운다. 댓글 총 개수는 `a.post_comments`가
   아니라 `p#comment_count` 텍스트("103 comments")에.
8. `/u/<name>`은 `/user/<name>`으로 302 — GET으로 따라가면 됨
   (HEAD 요청은 이 호스트에서 HTTP/2 깨짐, GET만 쓸 것).
9. 링크가 전부 **인스턴스 상대경로** (`/r/...`) → permalink는
   `https://www.reddit.com` 접두을 붙여 정규화. 본문 속 외부 링크는
   rewriting 안 됨.

---

## 3. 엔진 설계로 증류한 원칙

1. **엔진 순서 = (신선함 × 저렴함)**: oauth(설정 시 — ratio 포함 라이브
   풀데이터) → redlib(라이브 점수, 1요청) → rss(+arctic 점수보강,
   2요청) → arctic/pullpush(아카이브 단독).
2. **같은 명세(record schema)를 모든 엔진이 채운다.** 어느 엔진이
   답했는지 `engine` 메타 + 필드 단위 `score_source`로 표시. 근사치는
   드러내라 (live vs archive).
3. **429/봇벽은 상태코드만으로 판단하지 않는다** — 본문/타이틀 마커
   검사. 200 + "Oh noes!" = 죽은 것이다.
4. **실패한 엔진과 재시도로 싸우지 않는다** — 다음 엔진으로 넘어간다.
   재시도는 Retry-After 존중 3회까지, 그만.
5. **스로틀 상태를 디스크에 저장**해 연속 CLI 호출도 예의를 지키게
   (rss 5초/호스트). 캐시 TTL 기본 300초.
6. **요청 수 O(1)+1**: 목록 1회 + ids 일괄 보강 1회 (100개당).

## 4. 기존 도구 지형 (2026-09 서브에이전트 실측 조사)

"바퀴 재발명인가?" — 아니었다. 두 절멸 사건(2023 API 유료화,
2026-07 old.reddit 로그인 웰)이 클라이언트 무덤을 만들었다:

- **죽음**: rtv(4.6k★, 아카이브, "Forbidden"만 출력), tuir(2020년부터
  방치, 동일 증상), snoowrap/raw.js/JRAW/psaw(전부 사망 또는 삭제)
- **살았으나 계정 필수**: oh-my-reddit(브라우저 쿠키 탈취 방식),
  rdt-cli(쿠키+리버스 엔지니어링), ttrv·terminally-online 등(praw식
  자기 OAuth)
- **살았으나 조용히 고장**: devskim(403을 삼켜 빈 목록 반환 — 작성자도
  인지 못함), redyt, reddit-tui(익명 모드는 old.reddit 로그인 웰로 사망,
  셀프호스팅 redlib 프록시로만 생존)
- **살아있는 익명 도구는 2개뿐**: radar(2★, RSS 피드만 — 스레드/점수
  없음), reddit-rs(2★, redlib 단일 엔진 팬아웃)
- **부분 재료만 존재**: praw(익명 그랜트 지원하나 CLI 없음),
  gallery-dl(공개 client_id 내장하나 기본값은 막힌 REST — oauth 명시
  필요), arctic_shift(API는 익명 개방이나 **CLI 자체가 없음**)

교훈(무덤이 말해주는 것): **단일 엔드포인트에 경직된 클라이언트는 그
엔드포인트가 막히는 날 죽는다**(rtv→.json, reddit-tui→old.reddit,
devskim→hot.json). 살아남은 설계는 엔드포인트-불가지론(RSS, 자체
OAuth, 프록시)뿐. 이 CLI의 4-엔진 자동 폴백이 이 지형에서 유일하게
"조합"을 차지한다 — 에이전트 툴링 진영(Agent-Reach 83k★)조차 라우팅
테이블에 "reddit: 제로-설정 경로 없음"으로 기록 중.

## 5. 이 노하우가 썩었는지 재점검하는 법 (반복 절차)

```bash
# redlib 생존/봇벽 확인 (200이어도 title 확인)
curl -sS -A "$UA" https://redlib.ducks.party/r/python | grep -o '<title>[^<]*'
# RSS 살아있나
curl -sS -A "$UA" 'https://www.reddit.com/r/python/hot.rss?limit=2' | head -c 200
# arctic 살아있나
curl -sS 'https://arctic-shift.photon-reddit.com/api/posts/ids?ids=t3_1wi6dpv' | head -c 200
# .json이 뚫려있는지도 가끔 확인 (뚫리면 엔진 교체)
curl -sS -A "$UA" -o /dev/null -w '%{http_code}\n' 'https://www.reddit.com/r/python/hot.json?limit=1'
```

결과가 바뀌었으면: 이 문서의 표를 고치고, 엔진 순서를 재논의하고,
smoke-test를 다시 돌린다. `smoke-test.sh`가 이 점검의 자동화다.
