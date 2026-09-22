# mailplug CLI — KNOWHOW (프로브 전 기록)

작성: 2026-09-22 · 계정: mcpark@livemolo.me (라이브몰로 그룹웨어, 메일플러그 호스팅)

## 배경 — 왜 웹 API인가

himalaya(IMAP) 연동 시도 → 서버가 거부:
```
IMAP LOGIN failed: NO 553 sorry, that password allowed relay (#5.7.5)
```
- 앱 비밀번호/계정 비밀번호 모두 동일 553. POP3(poplib)도 동일.
- 원인: 그룹웨어 관리자의 POP3/IMAP 릴레이 설정 미개방 (mcpark는 관리자 아님, `/mail/admin/pop3` → "접근 권한이 없습니다").
- 메일플러그 공식: 2025-04-01 이후 개통 그룹웨어는 IMAP 제한 정책 존재.
- 결론: 프로토콜 경로는 폐쇄 → 웹 그룹웨어의 내부 REST API로 우회.

## API 발견 과정 (CDP 실측)

1. XHR 후킹(`XMLHttpRequest.prototype.open/send`, `window.fetch` 랩)으로
   gw.mailplug.com SPA의 데이터 호출 캡처:
   - `GET https://m59.mailplug.com/api/v2/mail/mailboxes` — 메일함
   - `GET .../mailboxes/{id}/messages?limit&search&searchTarget` — 목록/검색
   - `GET .../mailboxes/{id}/messages/{mid}` — 본문(HTML)
   - 검색 파라미터는 UI 검색창에 React native setter로 값 주입 + Enter
     keydown 발사로 유도해 캡처 (`search=키워드&searchTarget=all`).
2. 인증: XHR `setRequestHeader` 후킹으로 `DPoP: eyJ0eX...` 헤더 발견 →
   OAuth-ish로 보였으나, **순수 fetch(credentials:'include')로도 200** →
   쿠키 인증만으로 충분함을 확인 (DPoP는 특정 엔드포인트만).
3. 브라우저 밖 재현: `agent-browser --cdp 9222 --json cookies get`로
   `.mailplug.com` 쿠키(MP_SES/MP_AUT/MP_TAG) 추출 → stdlib urllib로
   `m59.mailplug.com` 호출 200 성공. **Referer/Origin: gw.mailplug.com 필수.**
4. 발송 스키마: compose 화면에서 받는사람/제목 채우고 '임시 저장'/'보내기'
   클릭 → `POST /api/v2/mail/sendMail` 바디 캡처:
   - 임시저장: `transferMode:"save"`, 발송: `transferMode:"send"`
   - 최소 발신 스키마(외부 주소): `toRecipients:[{isValid:true,displayName:"",emailAddress:...}]`
   - 검증: 자기 자신에게 실발송 → 보낸편지함 id=39 등록 + `resp.messageId` 반환 확인.

## 함정 (실측)

- **발송 실패는 400 + `{"error":{"code":730105,"message":...}}`**: 빈 수신자·malformed 주소
  모두 400으로 온다 (200 오탐 방지 — 성공은 `{"messageId":N}` 스키마로만 판정).
- **본문 HTML 주의**: `<b>` 등 태그는 그대로 HTML로 렌더됨(의도적 사용 가능).
  `<script>`는 서버가 자동 제거(살균). `&`는 엔티티로 써야 의도 렌더.
- **페이지네이션은 `offset` 파라미터**: `?limit=10&offset=10` → 다음 10통.
  `page` 파라미터는 무시됨. limit>전체개수면 전체 반환, limit<=0은 무시.
- **PATCH 응답은 빈 본문**: `PATCH .../messages/{id}` `{"messageFlag":"Y"}`는
  200 + empty body. json.loads("") ValueError를 exit 3(인증실패)로 오판하지
  말 것 → 빈 본문은 `{}`로 처리.
- **messageFlag 의미**: `N`=안읽음, `Y`=읽음. (`R` 아님 — IMAP `\Seen`과
  혼동 주의). unread 판정은 `flag == "N"`.
- **자기 자신에게 보낸 메일은 inbox가 아니라 '내게 쓴 편지함'(mailboxId 0)에
  즉시 등장**. 도착 검증은 `list self`로.
- **없는 messageId는 404가 아니라 400 Bad Request**. exit 4 매핑 필요.
- **mailboxId 고정값**(이 계정 기준): 0=내게쓴, 1=받은, 2=보낸, 3=휴지통,
  4=임시, 5=스팸. 문자열 id: unread/starred/allmail. 다른 테넌트에서는
  `/mailboxes` 응답의 `type` 필드(1~10)로 매핑하는 게 안전.
- **쿠키는 세션 쿠키**: 브라우저 재시작/로그아웃 시 소멸. CLI는 만료 시
  CDP에서 재추출하고, `~/.config/mailplug-cli/secret`에 비밀번호 있으면
  agent-browser로 재로그인까지 시도. 로그인 폼은 Cloudflare Turnstile가
  붙어있어 순수 HTTP 로그인 불가(브라우저 경유 필수).
- **본문은 `<mailplughtml><mailplugbody>` 래퍼 + 인라인 스타일 범벅**:
  정규식 태그 제거 전 `<br>/</p>/</div>`를 개행으로 치환해야 줄바꿈 보존.
- 발송 body는 일반 텍스트 전달 시 `\n` → `<br>` 치환 필요(서버가 HTML만 받음).

## 실패 경로 기록 (재프로브 시 참고)

- `imaps://imap.mailplug.co.kr:993` + sasl plain → `BAD invalid command`
  (PLAIN 미지원, LOGIN은 됨) → LOGIN으로 바꾸면 553 relay.
- `pop3.mailplug.co.kr:995` poplib → `+OK` 후 PASS 단계에서 553.
- `https://gw.mailplug.com/mail/settings/pop3`, `/settings/personal/pop3`,
  `/settings/integration` 등 → 404/리다이렉트. 실제 라우트는
  `_buildManifest.js`에서 `/mail/setting/pop3`, `/mail/admin/pop3`로 확인.
- `/mail/admin/pop3` → 접근 권한 없음(관리자 전용).
