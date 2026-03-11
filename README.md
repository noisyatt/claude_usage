# Claude Usage Widget

macOS 데스크톱 위젯으로 Claude 사용량을 실시간 모니터링합니다.

![macOS](https://img.shields.io/badge/macOS-14%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Rate Limits** — claude.ai 5시간/7일 사용량 퍼센티지 + 리셋 시간
- **ccusage 연동** — 일별/월별 비용, 토큰 수, 모델별 breakdown
- **자동 갱신** — 60초 폴링
- **Google OAuth 지원** — WKWebView 기반 로그인
- **Cloudflare 우회** — WKWebView가 JS challenge 자동 처리
- **콘텐츠 적응형 크기** — 위젯 높이가 내용에 맞게 자동 조절

## Requirements

- macOS 14+
- [ccusage](https://github.com/ryoppippi/ccusage) (`npx ccusage`)
- Claude Max plan (Pro/Team도 가능하나 ORG_ID 변경 필요)

## Install

```bash
make install
```

## Usage

```bash
# 실행
claude-usage-widget &

# 또는
make run
```

메뉴바 ◆ 아이콘에서 Show/Hide, Refresh, Logout, Quit 가능.
위젯 내 버튼으로도 Refresh/Login/Logout 가능.

## Configuration

환경변수로 ORG_ID를 오버라이드할 수 있습니다:

```bash
export CLAUDE_ORG_ID="your-org-id-here"
claude-usage-widget &
```

ORG_ID는 claude.ai에서 DevTools Network 탭에서 확인 가능합니다.

## Build

```bash
make build
```

단일 Swift 파일, 외부 의존성 없음. `swiftc`만 있으면 됩니다.
