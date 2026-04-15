---
name: Phase 4 착수 대기 — AceDB 프로파일 + LibSharedMedia
description: 2026-04-15 Phase 3 완료 커밋 6ddbecc. 다음 세션에서 Phase 4a(AceDB 프로파일 시스템 + LibSharedMedia 테마/사운드) 착수 예정.
type: project
---
## 상태 (2026-04-15 기준)

Phase 3 WoW 애드온 통합 탭창 + 펄스 애니메이션 구현 완료. 블로커 4건 + SUGGESTION/NITS 전부 패치 반영. 인게임 실기 테스트 미실시 (집 맥미니로 이관 예정). UX Gap 리서치 보고서 작성 완료(`docs/ADDON_UX_RESEARCH.md`).

**Why**: 업계 표준 애드온(WeakAuras/BigWigs/ElvUI/DBM) 대비 프로파일 시스템과 미디어 커스터마이징이 가장 큰 격차. 둘 다 사용자 가치 높고 다른 기능의 전제조건이라 Phase 4a 로 우선 착수.

**How to apply**: 다음 세션 시작 시 (1) HANDOFF.md 로 현재 상태 복원 (2) 인게임 실기 테스트 우선 여부 확인 (3) 확인되면 Phase 4a 착수 — AceDB-3.0 + LibDualSpec-1.0 + LibSharedMedia-3.0 편입 순서.

## 최신 Git 상태
- 브랜치: main
- 최신 커밋: `6ddbecc` (리서치: HealGuide 애드온 UX Gap 분석)
- 이전 커밋 체인: `24d42ca` (Phase 3 통합 탭창) → `b0121ab` (S-new-3 TTS 가드) → `c84281d` (HANDOFF 동적 경로) → `6ddbecc` (리서치)
- origin/main 동기화 완료

## 다음 작업: Phase 4a 착수 내용

### 목표
1. **AceDB 프로파일 시스템** — 직업/서버/캐릭터/프로파일 레벨 저장, LibDualSpec 자동 스펙 스왑
2. **LibSharedMedia 통합 (테마 + 사운드)** — 사운드/폰트/색상 커스터마이징, 배경색 피커

### 착수 트리거 문구
사용자가 다음 세션에서 이렇게 말할 예정:
> "Phase 4a 시작하자 — AceDB 프로파일 시스템 + LibSharedMedia 통합"
> 또는
> "ADDON_UX_RESEARCH.md 의 P1 항목 구현하자"

### 기술 결정 (리서치 보고서에서 확정된 것)
- **Ace3 부분 편입** (올인 아님) — LibDualSpec + LibSharedMedia 만 라이브러리화. 나머지는 순정 WoW API 유지
- **Storage 마이그레이션 필요** — 기존 `HealGuideCharDB` 구조를 AceDB 스키마로 이전 (`HealGuideDB.profiles[default]`). 현재 실사용자 없으므로 마이그레이션 코드는 단순화 가능
- **미디어 하드코드 제거** — AlertFrame.lua 의 `SetColorTexture(0,0,0,0.75)`, `PlaySound(888)`, `GameFontNormalLarge` 를 전부 LSM 조회로 교체

### 작업 순서 (P1 묶음)
1. `addon/HealGuide/Libs/` 폴더 신설 + Ace3 하위 라이브러리 다운로드
   - AceDB-3.0
   - LibStub
   - CallbackHandler-1.0 (AceDB 의존성)
   - LibDualSpec-1.0
   - LibSharedMedia-3.0
2. `HealGuide.toc` embeds 파일 추가
3. `Core/Storage.lua` 재작성 — AceDB 기반으로
   - `HealGuideCharDB` → `HealGuideDB` (프로파일 레벨 + 캐릭터 레벨 분리)
   - `Storage:Init()` 내부에 AceDB 초기화 + LibDualSpec 등록
   - 기존 API(`GetSetting/SetSetting`) 는 래퍼로 유지
4. `UI/MainFrame.lua` 설정 탭에 "프로파일" 섹션 추가
   - 드롭다운: 현재 프로파일 선택
   - 버튼: 새로 만들기 / 복사 / 삭제 / 리셋
5. `UI/MainFrame.lua` 설정 탭에 "테마" 섹션 추가
   - 드롭다운: 사운드 (LSM:List("sound"))
   - 드롭다운: 폰트 (LSM:List("font"))
   - 슬라이더: 폰트 크기
   - 버튼: 배경 색상 → ColorPickerFrame
   - 버튼: 텍스트 색상 → ColorPickerFrame
   - 버튼: 사운드 테스트 재생
6. `UI/AlertFrame.lua` 리팩토링
   - 배경 텍스처: Storage 에서 색상 읽어서 적용
   - 폰트: LSM:Fetch("font", name) 로 조회
   - 사운드: LSM:Fetch("sound", name) → PlaySoundFile
7. `addon/TESTING.md` 갱신 — 프로파일/테마 섹션 추가
8. luajit 문법 검증 + code-reviewer 리뷰

### 예상 작업량
2~3일 분량. 한 세션 안에 끝날 수 있지만 중간 실기 검증이 필요할 수 있음.

### 주의점
- Ace3 라이브러리 라이센스(LGPL/MIT) 확인 — 번들링 시 LICENSE 파일 포함
- LibStub 중복 방지 — 이미 다른 애드온이 로드하면 그 버전 사용
- 기존 `Storage:GetSetting("iconBaseSize")` 등 호출부가 많으므로 래퍼 유지 필수

## 관련 문서
- `docs/ADDON_UX_RESEARCH.md` — 전체 Gap 분석 + P1~P4 로드맵
- `HANDOFF.md` — 집 맥미니 세팅 + 인게임 테스트 가이드
- `addon/TESTING.md` — 현재 구현 검증 체크리스트
- `.claude/memory/phase3_addon_handoff.md` — Phase 3 최종 상태
- `.claude/memory/phase1_svs_pending.md` — Mac 앱 잔여 SUGGESTION

## 인게임 테스트 미완료 — 중요
Phase 4 착수 전에 반드시 실기 테스트를 선행해야 함. 이유:
- 현재 구현에 알려진 불확실 요소 3건 (TTS 필드명, EasyMenu deprecated, UIRadioButtonTemplate)
- 이게 실제 크래시를 낼 경우 Phase 4 위에서 디버깅하면 층이 두꺼워짐
- 또한 실기 피드백이 Phase 4 우선순위를 바꿀 수 있음 (예: "펄스 애니메이션이 너무 느리다" → 프레임 세부조정이 P1 으로 올라옴)
