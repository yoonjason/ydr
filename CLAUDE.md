# 프로젝트 규칙 — HealGuide

## 개요

WarcraftLogs 기반 WoW 힐러 가이드 시스템. 두 개의 하위 프로젝트:
- **app/** — SwiftUI macOS 앱 (로그 → Lua 데이터 생성기)
- **addon/** — 와우 인게임 Lua 애드온 (실시간 알림)

## 아키텍처

### app/
- **MVVM + 프로토콜 지향 의존성 주입**
- **SwiftUI** 단일 UI 계층 (macOS 14+)
- **XcodeGen** 기반 project.yml — `.xcodeproj` 는 gitignore
- 모든 외부 연동(Keychain, URLSession, WarcraftLogs API)은 **프로토콜로 추상화** 후 `init(...:)` 로 주입
- `@MainActor` ViewModel, `async/await` 우선

### addon/
- 순수 Lua 5.1 (WoW 런타임)
- 이벤트 기반: `COMBAT_LOG_EVENT_UNFILTERED`, `ENCOUNTER_START`, `PLAYER_SPECIALIZATION_CHANGED`
- 전역 네임스페이스 오염 최소화 — 로컬 테이블 안에 함수 캡슐화

## 코딩 규칙

### Swift
- `print()` 금지 → `os.Logger` 또는 별도 Log 래퍼 사용
- 네이밍: 타입 `PascalCase`, 변수/함수 `camelCase`
- 프로토콜은 `-able`, `-ing`, `-Protocol` 중 문맥에 맞게
- 주석 최소화 — 의도가 명확하지 않은 경우만 "왜" 를 남김
- Force unwrap 금지 (테스트 코드 제외)
- `@MainActor` ViewModel + 프로토콜 기반 의존성 → Mock 주입 가능해야 함

### Lua
- 전역 변수 생성 금지 — `local` 선언 기본
- 애드온 네임스페이스: `HealGuide = {}` 또는 `local addonName, addon = ...`
- 이벤트 핸들러는 기능별로 분리 (`onCombatLogEvent`, `onEncounterStart` 등)
- `/print` 디버그는 DEBUG 플래그로 토글

### Git
- 한글 커밋 메시지, 제목 50자 이내
- 기능 단위로 작은 커밋
- body 에 "왜(Why)" 위주로 작성, "무엇(What)" 은 diff 로 충분

## 데이터 포맷

### Lua 출력
최상위 전역: `HGPT_Data`
```lua
HGPT_Data["<SpecKey>"] = {
  [<encounterID>] = {
    [<bossSpellID>] = {
      { spellID = <playerSpellID>, delay = <seconds> },
      ...
    }
  }
}
```

### SpecKey
- `DiscPriest`, `HolyPriest`, `RestoDruid`, `MistweaverMonk`,
  `HolyPaladin`, `RestoShaman`, `PresEvoker`

### 스킬 식별은 항상 spell ID (숫자)
- 이름 직접 사용 금지 — 한/영 현지화 문제 방지
- 애드온은 `GetSpellInfo(spellID)` 로 런타임에 이름 조회

## 디렉토리

- `/app/HealGuide/App/` — 앱 진입점, AppDelegate
- `/app/HealGuide/Models/` — 도메인 모델 (`ReportURL`, `CastEvent`, `HealerSpec` 등)
- `/app/HealGuide/Services/` — 외부 연동, 파싱, 변환 서비스
- `/app/HealGuide/ViewModels/` — @MainActor ObservableObject
- `/app/HealGuide/Views/` — SwiftUI 뷰
- `/app/HealGuideTests/` — 단위 테스트
- `/addon/HealGuide/` — 와우 애드온 소스

## 비밀 정보

- **API Client Secret 은 반드시 Keychain 사용**
- `~/Library/Keychains` 에 service `com.yeongseok.healguide` 로 저장
- 소스에 하드코딩 금지

## 에이전트 활용 가이드

- **pm** — 요구사항 우선순위, DoD 검토, 스코프 조정
- **ios-engineer** (실제로는 macOS) — Swift 코드 작성, 아키텍처
- **qa-engineer** — 테스트 케이스, 엣지 케이스 식별
- **code-reviewer** — PR 전 코드 리뷰
- **tech-writer** — README/CHANGELOG, PROJECT_PLAN 업데이트

## 참고

- 전체 기획 + 기술 스펙 → [PROJECT_PLAN.md](./PROJECT_PLAN.md)
- WarcraftLogs API v2 문서: https://www.warcraftlogs.com/v2-api-docs/warcraft/
- WoW API: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
