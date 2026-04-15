---
name: Phase 1 SVS 잔여 개선 항목
description: Phase 1 SVS(URL→OAuth→FightMeta 표시) 완료 후 차기 반영 대기 중인 SUGGESTION/NITS 및 다음 슬라이스 후보
type: project
originSessionId: 4a7dc947-f6d7-404a-9304-284858c33969
---
Phase 1 SVS는 2026-04-15에 GO 판정으로 완료됨(36/36 테스트 통과, DoD 6항목 충족). 커밋은 T1~T5 단위 분할 완료.

**Why:** code-reviewer 최종 리뷰에서 모두 차기 반영 가능 수준(블로커 아님)으로 판정. 다음 슬라이스 전 또는 중 정리 권장.
**How to apply:** 다음 슬라이스 착수 전에 선택적으로 반영하거나, 사용자가 "잔여 개선 반영해줘" 요청 시 아래 항목을 ios-engineer에 일괄 dispatch.

## 잔여 개선 항목

- **S-1 onAppear 멱등성** — ReportViewModel.onAppear()가 사용자가 수정한 clientSecret을 Keychain 값으로 덮어쓸 위험. 수정안:
  ```swift
  guard clientSecret.isEmpty, let secret = keychain.load() else { return }
  clientSecret = secret
  ```
- **S-2 동시 호출 테스트 실행 순서 역전** — test_fetchFight_whileFetching_secondCallIsIgnored가 `Task { ... }` 이후 직렬 await 호출 순서 때문에 의도와 반대 시나리오를 통과시킴. 통과는 되지만 정확 검증이 아님. async let 또는 continuation 재구성 필요.
- **N-1 Preview 부족** — ContentView에 #Preview("idle")만 있음. fetching/success/failure 상태 Preview 보강하려면 ReportViewModel에 테스트 전용 init(state:) 오버로드 필요(private(set) 제약 때문).
- **N-2 테스트 주석 오해 유발** — test_fetchFight_whileFetching_secondCallIsIgnored의 주석이 실제 실행 순서와 반대. 주석 수정 필요.

## 다음 슬라이스 후보 (PM 위임 대기)

**CastEvents → 타임라인 정규화 → Lua 생성 → 클립보드 복사**
- Phase 1 본래 DoD의 나머지 절반. SVS 이후 자연스러운 다음 단위.
- 필요 작업: CastEvents GraphQL 쿼리, spell ID 기준 이벤트 정규화, HGPT_Data 포맷(최상위 전역 `HGPT_Data["<SpecKey>"][encounterID][bossSpellID]`) Lua 문자열 생성, NSPasteboard 복사, 스펙 자동 감지(actors API) 또는 Phase 2 이관 결정.

## 기타 보류 작업

- PROJECT_PLAN.md Phase 1 DoD 재작성 반영(PM이 제안한 구체화안 — 스펙 결정 방식, encounterID 출처, 에러 케이스 기준, Keychain 검증, Lua 정합성 기준 명시). tech-writer에 위임 가능.
- 실제 WarcraftLogs URL + 크레덴셜로 macOS 앱 수동 스모크 테스트 미수행.
