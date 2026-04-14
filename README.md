# HealGuide — WoW 힐링 가이드 시스템

WarcraftLogs 상위 파스 로그에서 힐러 타임라인을 추출해서, 인게임에서 **"보스 스킬 감지 → N초 뒤 무슨 힐 써!"** 를 실시간 알림으로 띄우는 시스템.

## 전체 흐름

```
[WarcraftLogs URL] → [맥 앱이 API 호출 + 분석] → [Lua 데이터 문자열]
                                                      │
                                                      ▼
                                              [Data.lua 에 붙여넣기]
                                                      │
                                                      ▼
[쐐기 던전 진행 중] → [보스 X 스킬 감지] → [N초 뒤 힐 Y 써!] 알림
```

## 구성

- **[app/](./app)** — SwiftUI macOS 네이티브 앱 (로그 분석 + Lua 데이터 생성기)
- **[addon/](./addon)** — 와우 인게임 애드온 (Lua, 전투 중 알림)

두 프로젝트는 독립적으로 빌드/배포되지만, 앱이 생성한 Lua 문자열을 애드온의 `Data.lua` 에 붙여넣는 방식으로 연결됩니다.

## 지원 스펙

- 사제: 수양(Discipline), 신성(Holy)
- 드루이드: 회복(Restoration)
- 수도사: 운무(Mistweaver)
- 성기사: 신성(Holy)
- 주술사: 복원(Restoration)
- 기원사: 보존(Preservation)

## 개발 단계

자세한 기획과 기술 스펙은 [PROJECT_PLAN.md](./PROJECT_PLAN.md) 참조.

현재: **Phase 1 — 앱 MVP 개발 준비 완료**

## 빌드

### macOS 앱 (app/)
```bash
cd app
brew install xcodegen  # 최초 1회
xcodegen generate
open HealGuide.xcodeproj
```

### 와우 애드온 (addon/)
`addon/HealGuide/` 폴더를 `~/.../World of Warcraft/_retail_/Interface/AddOns/` 에 복사.

## 개발 워크플로우

이 프로젝트는 **CraftBoy Workspace + Claude Code** 를 사용한 에이전트 기반 개발을 가정합니다.

1. CraftBoy Workspace 메뉴에서 이 프로젝트 폴더 등록
2. 권장 에이전트 활성화: `pm`, `ios-engineer`, `qa-engineer`, `code-reviewer`, `tech-writer`
3. "새 세션" 버튼으로 Claude Code 시작 → `PROJECT_PLAN.md` 의 Phase 1 단계부터 작업 요청
