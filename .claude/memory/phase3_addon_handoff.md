---
name: Phase 3 애드온 구현 완료
description: 2026-04-15 Phase 3 WoW 애드온 9개 파일 구현 완료 + 커밋. code-reviewer dispatch 진행 중, 인게임 실기 테스트 미실시.
type: project
originSessionId: a242d2a6-7364-45e9-a02c-5f49848d145d
---
## 상태 (2026-04-15 14:35 기준)

Phase 3 WoW 애드온 풀 구현 완료. 커밋 `76ebd05` — 12 files changed, 1138 insertions. 레거시 Main.lua / Data.lua 제거.

**Why**: 사용자가 Data.lua 수동 편집 방식을 폐기하고 Mac 앱 생성 import 문자열 → 인게임 붙여넣기 → SavedVariablesPerCharacter 저장 → ENCOUNTER_START 자동 활성 흐름으로 전환 결정. 한 캐릭터 여러 스펙 + 자동 swap + 비힐러 스펙 OFF 까지 포함.

**How to apply**: 애드온은 코드상 완성 상태이나 (1) code-reviewer 리뷰 미완료 (2) 인게임 실기 테스트 미완료. 다음 세션에서 code-reviewer 결과 반영 → 실기 테스트 → 버그 수정 순서 권장.

## 생성된 파일 구조

```
addon/HealGuide/
├── HealGuide.toc              ← SavedVariablesPerCharacter: HealGuideCharDB, Version 1.0.0
├── Data/
│   └── DungeonMappings.lua    ← encounterID → instanceMapID (TWW 시즌1)
├── Core/
│   ├── Init.lua               ← 이벤트 등록, 슬래시 명령어 라우팅
│   ├── Storage.lua            ← HealGuideCharDB CRUD + encounterIndex 자동 빌드
│   ├── SpecMatcher.lua        ← 7힐러 스펙 감지 + 비힐러 AUTO OFF
│   ├── ImportParser.lua       ← loadstring + setfenv(fn, {}) 샌드박스
│   └── EncounterEngine.lua    ← reactive/absolute/hybrid 모드, 타이머 관리
└── UI/
    ├── AlertFrame.lua         ← 드래그 가능 알림 + 페이드아웃 + /hg lock
    ├── ImportDialog.lua       ← 붙여넣기 다이얼로그 + 에러 표시
    └── MainFrame.lua          ← 트리뷰 CRUD (캐릭터→던전→보스→스펙)
```

## ImportParser 보안 설계
- 5MB 길이 상한
- 위험 패턴 거부: `require`, `os.`, `io.`, `function(`, `while`, `for`, `loadstring` 등
- `setfenv(fn, {})` 빈 환경 실행 (전역/upvalue 차단)
- 결과 테이블 구조 검증 (version, dungeonName, spec, bosses)

## 슬래시 명령어
- `/hg import` — 붙여넣기 다이얼로그
- `/hg test <encID>` — 시뮬레이션
- `/hg lock` — 알림 프레임 드래그 잠금

## 진행 중 / 대기

- **code-reviewer dispatch**: `code-reviewer_20260415_143157.task` 진행 중. 9개 파일 리뷰 — Lua 문법/WoW API/보안/타이머/UI 체크.
- **인게임 실기 테스트**: 미실시. 다음 세션에서 테스트 가이드대로 진행 필요. 테스트 URL: https://www.warcraftlogs.com/reports/XqwA2yHChmM87GjR?fight=3 (수양 사제, 4보스 M+).
- **Mac 앱 SUGGESTION 패치**: 미처리. S-1 ISO8601 formatOptions, S-2 레이드 dungeonName 한계, N-1 Mock 튜플 라벨.

## 디버깅 학습 (보존)
- WCL API `HostilityType` enum: `Friendlies`/`Enemies`
- M+ vs 레이드 분기: `dungeonPulls` 비어있지 않으면 M+
- M+ fight 도 encounterID > 0 을 가지므로 encounterID 로는 분기 불가
