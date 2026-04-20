---
name: 스킬 선택 기본값은 전체 해제
description: 로그 분석 탭 주문 선택 UI에서 기본값은 빈 선택 — 전체 선택 금지
type: feedback
originSessionId: c97ec765-7dfa-452f-9bfa-92ba583be65d
---
로그 분석 탭 스킬 선택 화면(`ReportViewModel.advanceToSpellSelection`)에 진입할 때 `selectedSpellIDs` 는 빈 Set 으로 시작해야 한다. 전체 카탈로그를 기본 선택해 두지 않는다.

**Why:** 사용자는 "자신이 체크한 스킬만" 인게임 알림으로 받기를 원한다. 기본값이 전체 선택이면 생성 버튼을 누를 때마다 전체 해제부터 해야 하는 번거로움이 있고, 실수로 생성하면 인게임에서 모든 스킬이 알림으로 떠서 쓸모없어진다. 사용자가 같은 요청을 과거에도 한 번 했으나 반영되지 않아 재요청했다.

**How to apply:** 스킬 선택 UI 계열(향후 다른 탭에서도 유사 UI가 생기면) 기본값은 항상 빈 선택. "전체 선택" 은 명시적 버튼(`checkAllSpells`) 으로만 트리거. 이 규칙은 랭커 수집/탤런트 빌드 등 다른 선택 UI에도 동일하게 적용.
