---
name: dmg 패키징은 명시적 요청 시에만
description: Release 빌드 후 dmg 자동 생성 금지 — 사용자가 직접 요청할 때만 수행
type: feedback
originSessionId: c97ec765-7dfa-452f-9bfa-92ba583be65d
---
HealGuide 맥앱의 dmg 배포 패키징은 사용자가 명시적으로 요청한 경우에만 수행한다. 코드 수정 → 재빌드 → dmg 재생성을 선제적으로 제안하거나 자동 수행하지 않는다.

**Why:** 사용자는 필요한 타이밍에만 배포물을 만든다. 매 변경마다 dmg 를 새로 뽑는 것은 불필요한 빌드/디스크 사용이고, 사용자 자신도 어느 dmg 가 최신인지 혼동될 수 있다.

**How to apply:** 맥앱 코드/UI 수정 후에는 "빌드하면 반영됩니다" 까지만 알리고 마무리. dmg 재생성이 필요한지 먼저 묻지도 말 것. 사용자가 "dmg 떨궈줘" "배포본 만들어" 등 명시적으로 요청할 때만 Release 빌드 + hdiutil 패키징 수행.
