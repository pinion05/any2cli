# mailplug — 라이브몰로 메일플러그 웹메일 CLI

메일플러그 그룹웨어 웹메일(gw.mailplug.com)을 터미널에서 읽고 보내는 CLI.
IMAP/POP3가 관리자 정책으로 막혀 있어(553 relay) 웹 내부 API를 사용한다.
인증은 로컬 Chrome CDP(9222, 클론 프로필) 세션 쿠키를 자동 추출한다.

## 요구사항

- Chrome CDP 9222에 gw.mailplug.com 로그인 세션 (agent-browser로 유지)
- Python 3 stdlib만 사용 (의존성 없음)
- `~/.local/bin`에 심볼릭 링크

## 사용법

```bash
mailplug folders                          # 메일함 목록 (안읽음 카운트)
mailplug list inbox --limit 10            # 받은 메일 최근 10통
mailplug list inbox --page 2              # 다음 페이지 (offset)
mailplug list unread                      # 안읽음만
mailplug list inbox --search 콘텐츠랩     # 검색
mailplug read 36                          # 본문 보기 (발신자 포함)
mailplug read 36 --mark-read              # 읽고 읽음 처리
mailplug send someone@example.com --subject 제목 --body 내용
mailplug send a@b.com --subject 제목 --body-file letter.txt --dry-run
```

본문 참고: `--body`의 HTML 태그는 그대로 렌더됨 (`<b>굵게</b>` 사용 가능,
`<script>`는 서버가 제거). 줄바꿈은 자동 `<br>` 변환.

출력 포맷: `--format table|json|jsonl|md` · exit: 0 성공 / 2 사용자 오류 /
3 인증·차단 / 4 찾을 수 없음.

## 세션 만료 시

CLI가 exit 3을 내면:
1. `agent-browser --cdp 9222 open https://login.mailplug.com/` → 로그인
   (mcpark@livemolo.me, 비밀번호는 사용자 확인 필요)
2. 재실행하면 쿠키를 자동 재추출한다.

`~/.config/mailplug-cli/secret`에 비밀번호를 저장해두면(권장하지 않음)
CLI가 agent-browser로 재로그인까지 자동 시도한다.

## 개발

- smoke-test: `bash examples/mailplug/smoke-test.sh` (실계정 라이브 호출,
  자기 자신에게 테스트 메일 1통 발송 포함)
- 프로브 기록: `KNOWHOW.md`
