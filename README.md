# Claude Usage Widget

macOS 데스크톱 위젯으로 Claude 사용량을 실시간 모니터링합니다.

![macOS](https://img.shields.io/badge/macOS-14%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Rate Limits** — claude.ai 5시간/7일 사용량 퍼센티지 + 리셋 시간
- **ccusage 연동** — 일별/월별 비용, 토큰 수, 모델별 breakdown
- **자동 갱신** — 60초 간격 폴링
- **Google OAuth 지원** — WKWebView 기반 로그인 (팝업 처리 포함)
- **Cloudflare 우회** — WKWebView가 JS challenge 자동 처리
- **콘텐츠 적응형 크기** — 위젯 높이가 내용에 맞게 자동 조절
- **앱 번들** — 일반 macOS 앱처럼 Dock 표시, Cmd+Q 종료

## Architecture

단일 Swift 파일(`ClaudeUsageWidget.swift`)로 구성되며 외부 의존성이 없습니다.

```
┌─────────────────────────────────────┐
│         Claude Usage Widget         │
├──────────┬──────────┬───────────────┤
│ Rate     │ ccusage  │ Widget HTML   │
│ Limits   │ Data     │ (WKWebView)   │
├──────────┴──────────┴───────────────┤
│         PageNavigator               │
│  (hidden WKWebView + cookie store)  │
├─────────────────────────────────────┤
│  WKWebsiteDataStore.default()       │
│  (세션 공유: login ↔ API fetch)      │
└─────────────────────────────────────┘
```

### 핵심 구성요소

| 클래스 | 역할 |
|--------|------|
| `PageNavigator` | hidden WKWebView로 API URL에 직접 접근, 페이지 콘텐츠 읽기 |
| `WeakScriptMessageHandler` | 위젯 HTML 버튼 → Swift 콜백 (retain cycle 방지) |
| `AppDelegate` | 상태바, 위젯 창, 로그인 창, 데이터 fetching 총괄 |

### 데이터 소스

1. **claude.ai Usage API** — `WKWebView`로 API URL에 직접 네비게이션 후 `document.body.innerText`로 JSON 읽기
2. **ccusage** — `Process`로 `npx ccusage daily/monthly --json --breakdown` 실행

### 로그인 흐름

```
앱 시작 → API fetch 시도
  ├─ 성공 → 데이터 표시, 60초 타이머 시작
  └─ /login 리다이렉트 → 로그인 창 표시
       ├─ Google OAuth 팝업 지원 (WKUIDelegate)
       └─ 별도 probe WKWebView로 5초마다 로그인 감지
            └─ 성공 → navigator 재생성, 로그인 창 닫기, 데이터 표시
```

### Cloudflare 우회

`curl`이나 직접 API 호출은 Cloudflare에 의해 차단됩니다.
`WKWebView`는 실제 Safari 엔진이므로 JS challenge를 자동으로 통과합니다.

## Requirements

- macOS 14+
- Xcode Command Line Tools (`swiftc`)
- [ccusage](https://github.com/ryoppippi/ccusage) (`npx ccusage`)
- Claude Pro/Max/Team 플랜

## Quick Start

```bash
# 클론
git clone https://github.com/noisyatt/claude_usage.git
cd claude_usage

# 앱 번들 빌드 (.app)
make app

# /Applications에 설치
make install-app

# 또는 CLI 바이너리만 설치
make install
```

## Usage

### 앱으로 실행
Finder에서 `Claude Usage.app` 더블클릭 또는:
```bash
open "Claude Usage.app"
```

### CLI로 실행
```bash
claude-usage-widget &
```

### 위젯 조작
- **메뉴바 ◆** — Show/Hide Widget, Refresh, Logout, Quit
- **위젯 버튼** — Refresh (데이터 갱신), Login/Logout (상태에 따라 전환)
- **Cmd+Q** — 앱 종료
- **드래그** — 위젯 위치 이동 가능

## Configuration

환경변수로 ORG_ID를 설정할 수 있습니다 (팀원별 다른 조직):

```bash
export CLAUDE_ORG_ID="your-org-id-here"
```

ORG_ID 확인 방법: claude.ai에서 DevTools → Network 탭 → `usage` 요청 URL에서 확인

## Build Targets

| 명령 | 설명 |
|------|------|
| `make build` | 바이너리 빌드 |
| `make app` | .app 번들 생성 |
| `make icon` | 앱 아이콘 생성 |
| `make install` | `~/.local/bin`에 바이너리 설치 |
| `make install-app` | `/Applications`에 앱 설치 |
| `make run` | 빌드 후 바로 실행 |
| `make clean` | 빌드 산출물 삭제 |
| `make uninstall` | 설치된 파일 삭제 |

## Troubleshooting

### 로그인 후 데이터가 안 뜸
- Logout → 다시 Login 시도
- 앱 종료 후 재시작

### session_invalid 에러
- 세션 만료됨. Logout 후 재로그인하면 자동으로 navigator가 재생성됩니다.

### 앱 아이콘이 안 보임
```bash
# 아이콘 캐시 초기화
killall Dock
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "/Applications/Claude Usage.app"
```

## License

MIT
