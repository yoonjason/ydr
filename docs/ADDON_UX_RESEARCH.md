# HealGuide 애드온 UX Gap 분석

작성일: 2026-04-15
현재 커밋: `c84281d`
리서치 방식: 메인 Claude 직접 WebSearch + 업계 표준 애드온(WeakAuras, BigWigs, DBM, ElvUI, Plater) 기능 비교

## 요약

현재 HealGuide 는 통합 탭창(데이터/설정/미리보기), 펄스 애니메이션, 펄스 2슬라이더, TTS, 기본 슬래시 명령어까지 구현돼 있어 **MVP 기준으로는 경쟁력 있는 편**입니다. 다만 업계 표준과 비교하면 다음 축에서 아직 빈 곳이 있습니다:

- **프로파일**: 캐릭터 단위만 지원. 업계 표준(AceDB-3.0)은 Default/Class/Realm/Char/Custom + 자동 스펙 스왑(LibDualSpec) 까지
- **프리셋/템플릿**: 없음. 추천 설정 복원 불가
- **테마/미디어**: 하드코드 (배경 검정, 글꼴 WoW 기본, 사운드 PlaySound 888). LibSharedMedia 미통합
- **조건부 로딩**: 힐러 스펙만. WeakAuras 는 10개+ 로드 조건
- **프레임 세부조정**: 위치/크기 만 노출. 스케일·투명도·스트라타·오프셋 미지원
- **디버그 뷰**: `DEBUG=false` 플래그만. 최근 이벤트 타임라인 viewer 없음
- **키바인드**: 전무 (자동 시전은 정책 차단, 토글 바인딩은 가능)
- **Blizzard Options 통합**: 미등록. Esc → 인터페이스에서 HealGuide 가 안 보임

아래 항목별로 상세 분석합니다.

---

## 1. 프로파일 시스템

### 업계 표준
- **AceDB-3.0**: 업계 표준 라이브러리. 다섯 가지 스토리지 타입 제공:
  - `profile` — 사용자가 선택한 프로파일 (복수 캐릭터 공유 가능)
  - `char` — 캐릭터별 격리
  - `class` — 같은 직업 캐릭터 공유
  - `realm` — 같은 서버 캐릭터 공유
  - `faction` — 진영 공유
- **LibDualSpec-1.0**: AceDB 에 자동 스펙 스왑 추가. `PLAYER_SPECIALIZATION_CHANGED` 에서 특정 프로파일로 자동 전환
- 실제 사용 예: WeakAuras, BigWigs, DBM, ElvUI 전부 AceDB 기반. DBM-Profiles 같은 보조 애드온으로 프로파일 복사/공유
- UI 패턴: "프로파일 선택 드롭다운 / 복사하기 / 삭제하기 / 리셋하기 / 새로 만들기"

### 현재 HealGuide
- `SavedVariablesPerCharacter: HealGuideCharDB` 로 캐릭터별 격리만
- 같은 캐릭터 여러 스펙은 같은 DB 공유 (스펙 스왑 시 내부 필드만 교체)
- 프로파일 개념 자체가 없음 → 같은 직업 캐릭터 간 설정 공유 불가, 리셋 불가

### Gap
- (大) 같은 직업 캐릭터(예: 수양/신성 사제 2개)에 동일 설정 이식 불가
- (大) "기본값으로 리셋" 기능 없음 (Storage 초기화만 가능, 수동)
- (中) 프로파일 복사 불가
- (小) 스펙 스왑 시 프로파일 자체는 안 바뀜 — 현재 스펙 스왑은 활성 데이터만 바뀌므로 대부분 케이스 커버됨

### 구현 방향
- Ace3 라이브러리 통합 (LibStub + AceDB-3.0) — 애드온 폴더에 Libs/ 추가
- 기존 `HealGuideCharDB` → `HealGuideDB` 로 이전 + AceDB 초기화
- 설정 탭에 "프로파일" 섹션 추가 (드롭다운 + 복사/삭제/리셋)
- LibDualSpec 추가로 힐러 스펙 간 자동 스왑

### 난이도/가치
- 난이도: **중** (Ace3 라이브러리 편입 + 기존 Storage 재작성)
- 가치: **높음** (여러 캐릭터/스펙 운영 유저에게 필수)

---

## 2. 프리셋/템플릿

### 업계 표준
- **BigWigs**: 보스별 음성 프로파일, "Emphasize" 플래그 프리셋, 직업 역할별 기본값
- **WeakAuras**: Wago.io 에서 커뮤니티 템플릿 import (프로파일 수준 export 가능)
- **DBM-Profiles**: 추천 프로파일 패키지 (탱/힐/딜 기본 설정)
- **ElvUI**: 설치 시 레이아웃 마법사 (Healer/Tank/DPS/Physical/Caster)

### 현재 HealGuide
- 프리셋 개념 없음. 첫 로드 시 `DEFAULT_SETTINGS` 가 전부

### Gap
- (中) 힐러 7스펙이 모두 같은 기본값 사용 → 사제와 성기사의 반응 스타일이 다른데 같은 값
- (中) "초보자용 / 숙련자용 / 시각만 / 음성만" 같은 테마 프리셋 없음
- (小) 커뮤니티 공유 템플릿 생태계 아직 없음

### 구현 방향
- `Data/Presets.lua` 신규 파일
- 구조: `PRESETS = { {name="기본", settings={...}}, {name="TTS 중심", settings={...}}, ... }`
- 설정 탭에 "프리셋 불러오기" 드롭다운
- `ApplyPreset(name)` 에서 DEFAULT_SETTINGS 덮어쓰기

### 난이도/가치
- 난이도: **하** (UI + 정적 데이터)
- 가치: **중** (첫 경험 개선, 권장 설정 명확화)

---

## 3. 키바인드 (자동 시전 제외)

### 업계 표준
- 모든 설정 창이 `BINDING_HEADER_*` / `BINDING_NAME_*` 글로벌로 키바인드 등록
- 예시 바인딩: "설정창 토글", "알림 테스트 발사", "알림 프레임 잠금", "전체 비활성"
- 플레이어는 와우 메뉴 → 키 바인딩 → 애드온 탭에서 설정

### 정책상 불가능한 것
- 상황에 따라 "다음 쓸 스킬" 이 자동 시전되는 키바인드 → `CastSpellByID` 가 protected, `InCombatLockdown` 제약으로 동적 전환 불가
- **결론: 자동 시전 기능은 고려 제외** (사용자 확인)

### 현재 HealGuide
- 키바인드 등록 없음. 슬래시 명령어만

### Gap
- (中) "설정창 열기" 만이라도 키바인드 되면 `/hg` 타이핑보다 훨씬 빠름
- (小) "알림 테스트 발사" 키바인드는 설정 튜닝 시 유용

### 구현 방향
- `Core/Bindings.lua` (또는 Init.lua 말미에 추가)
- 글로벌 정의:
  ```lua
  BINDING_HEADER_HEALGUIDE = "HealGuide"
  BINDING_NAME_HEALGUIDE_TOGGLE  = "설정창 열기/닫기"
  BINDING_NAME_HEALGUIDE_TESTALERT = "알림 테스트 발사"
  BINDING_NAME_HEALGUIDE_LOCK    = "알림 프레임 잠금 토글"
  ```
- `.xml` 파일에 Button 등록 (WoW 바인딩 프레임워크 요구사항)
- OnClick 에서 `MainFrame:Toggle()` / `AlertFrame:ShowAlert(17)` / `AlertFrame:ToggleLock()` 호출

### 난이도/가치
- 난이도: **하** (정적 선언)
- 가치: **중** (조작 편의성)

---

## 4. 테마/색상 (미디어 커스터마이징)

### 업계 표준
- **LibSharedMedia-3.0**: 폰트/사운드/텍스처/보더/스테이터스바를 여러 애드온 간 공유
- SharedMedia 폴더(`SharedMedia_MyMedia`) 에 사용자가 mp3/ttf/tga 드롭해서 모든 애드온에서 공용 사용
- WeakAuras/BigWigs/ElvUI 전부 LSM 통합: 드롭다운에서 폰트/사운드 선택 시 전 애드온 공용 목록 출현
- 색상 피커: `ColorPickerFrame` (와우 내장) + `ChangedCallback`

### 현재 HealGuide
- 알림 배경: 하드코드 `SetColorTexture(0, 0, 0, 0.75)` (AlertFrame.lua:22)
- 폰트: `GameFontNormalLarge` (WoW 기본)
- 사운드: `PlaySound(888)` 하드코드 (AlertFrame.lua:144)
- 보더: BasicFrameTemplateWithInset 기본값

### Gap
- (大) 사용자가 사운드를 바꿀 수 없음 (DBM 보이스팩 대체 불가)
- (中) 알림 배경/글꼴 색상 변경 불가 → 야간/밝은 화면 최적화 안 됨
- (中) LSM 미통합 → 다른 애드온과 미디어 공유 불가

### 구현 방향
- LibSharedMedia-3.0 라이브러리 편입 (`Libs/LibSharedMedia-3.0/`)
- AlertFrame 에서 배경/폰트/사운드를 Storage 설정 → LSM 조회로 해석
- 설정 탭에 "테마" 섹션 추가:
  - 사운드 드롭다운 (LSM:List("sound"))
  - 폰트 드롭다운 (LSM:List("font"))
  - 폰트 크기 슬라이더
  - 배경 색상 버튼 → ColorPickerFrame 호출
  - 텍스트 색상 버튼
- 개별 알림 모드(reactive/absolute/hybrid) 별로 다른 사운드 허용 (BigWigs 패턴)

### 난이도/가치
- 난이도: **중** (LSM 편입 + 색상 피커 콜백)
- 가치: **높음** (접근성 + 개인화, 첫 인상 좌우)

---

## 5. 조건부 표시

### 업계 표준
- **WeakAuras Load 탭**: 8종 조건
  - In Combat / 존재(Alive) / 경험치 중단(Afk) / 스텔스 / 마운트
  - 클래스 / 스펙 / 탤런트
  - 인스턴스 타입 (World/Party/Raid/PvP/Arena)
  - 존 (이름/ID)
  - 그룹 타입 (솔로/파티/레이드)
  - 파티/레이드 멤버 수
  - 파티원 역할 (힐러가 몇 명 있는가)
- 이 조건이 전부 충족돼야 aura 가 "loaded" 상태가 됨

### 현재 HealGuide
- 힐러 스펙 체크만 있음 (`SpecMatcher:IsHealer()`)
- 비힐러 스펙 → 알림 OFF, EncounterEngine:Cancel()
- **던전 밖에서는 어차피 ENCOUNTER_START 가 안 떠서 알림이 안 나오지만**, OnZoneChanged 는 존 진입 시 "던전 N개 활성" 토스트를 출력 → 조건 없음

### Gap
- (中) PvP (전장/투기장) 진입 시에도 토스트 메시지 출력 — 혼란 유발
- (中) "레이드에서는 off, M+ 에서만 on" 같은 세분화 불가
- (小) 솔로 상태(개인 테스트) 에서 토스트 뜸
- (小) 난이도(Normal/Heroic/Mythic/M+) 기반 분기 불가

### 구현 방향
- Storage settings 에 조건 필드 추가:
  ```lua
  conditions = {
      enabledInstances = { party=true, raid=true, pvp=false, arena=false },
      requireGroup     = false,  -- 파티/레이드에서만
      minGroupSize     = 0,
      allowedDifficulty = { [23]=true, [8]=true, ... },  -- M+ / Mythic Raid
  }
  ```
- `EncounterEngine:OnEncounterStart` 진입부에 `ShouldActivate()` 가드
- `GetInstanceInfo()` + `UnitInParty` + `UnitInRaid` + `difficultyID` 체크
- 설정 탭에 "활성 조건" 섹션 — 체크박스 그리드

### 난이도/가치
- 난이도: **하-중** (WoW API 조합만)
- 가치: **중** (특정 유저에게 필수, 일반 유저에게 중립)

---

## 6. 사운드 옵션 (LibSharedMedia 통합)

### 업계 표준 (4번과 부분 중복)
- BigWigs 사운드 카테고리: BW Alarm / BW Alert / BW Info / BW Long / BW Warning
- 각 카테고리별로 개별 파일 지정 가능
- 보이스팩 플러그인(BigWigs-VoicePack-\*) 으로 한국어 보이스 등 가능
- WeakAuras: 액션 발동 시 `SOUNDKIT` ID 또는 커스텀 파일 경로

### 현재 HealGuide
- `PlaySound(888)` — SOUNDKIT.READY_CHECK (ding 소리) 하드코드
- TTS 는 별도 경로 (`C_VoiceChat.SpeakText`)
- 사운드 파일 업로드/교체 불가

### Gap
- (大) 사운드 커스터마이징 불가 — 가장 많이 요청될 기능
- (中) 알림 타입별(reactive/absolute/hybrid) 차별화 사운드 없음
- (小) 음량 조절 없음 (시스템 볼륨만)

### 구현 방향 (4번과 공유)
- LSM 통합 + AlertFrame:_PlayAlertSound() 래퍼
- 설정 탭에 "사운드" 하위 섹션:
  - 사운드 드롭다운 (LSM sound list)
  - 볼륨 슬라이더 (0-100, PlaySoundFile 의 `channel` + `volume` 파라미터 활용)
  - 테스트 재생 버튼
- 모드별 다른 사운드 허용 (optional advanced)

### 난이도/가치
- 난이도: **중** (LSM + PlaySoundFile API 제약)
- 가치: **높음**

---

## 7. 프레임 설정 세분화

### 업계 표준
- ElvUI 프레임 에디터 패턴: 앵커 지점(TOPLEFT/CENTER/...), 상대 프레임, X/Y 오프셋, 스케일, 투명도, 프레임 스트라타(BACKGROUND~TOOLTIP), 프레임 레벨
- WeakAuras display 옵션: Width/Height/Anchor/Self Anchor/Parent/X/Y/Scale/Alpha/Sound/Animation/Glow
- 드래그 시 격자 스냅(snap to grid) 지원

### 현재 HealGuide
- 위치: drag + ClearAllPoints/SetPoint (점 1개, offset 2개)
- 크기: iconBaseSize / iconPulseSize 슬라이더
- 스케일: 없음 (크기 슬라이더로 간접 대체)
- 투명도: 없음 (페이드아웃 2초 고정)
- 프레임 스트라타: `HIGH` 하드코드 (AlertFrame.lua:13)

### Gap
- (中) 투명도 조절 불가 → "보여주되 시야 방해 최소화" 요구 대응 불가
- (中) 프레임 스트라타 고정 → 다른 UI(BossFrame 등)와 겹치면 선택 불가
- (小) 스케일 독립 조절 불가 (아이콘 크기로 대체 가능)
- (小) 앵커 지점 고정 CENTER — 화면 해상도 변경 시 위치 깨짐

### 구현 방향
- 설정 탭 "알림 위치" 그룹 확장:
  - 앵커 드롭다운 (9지점)
  - X/Y 오프셋 입력 필드 (드래그와 동기화)
  - 스케일 슬라이더 (0.5-2.0)
  - 투명도 슬라이더 (0.2-1.0)
  - 프레임 스트라타 드롭다운 (BACKGROUND/LOW/MEDIUM/HIGH/DIALOG/FULLSCREEN/FULLSCREEN_DIALOG/TOOLTIP)
- AlertFrame 에 `ApplyFrameSettings()` 메서드

### 난이도/가치
- 난이도: **하** (기존 슬라이더 패턴 복제)
- 가치: **중** (파워 유저에게 어필)

---

## 8. 디버그/로깅

### 업계 표준
- **DebugLog**: `/dl`, `/dle` (이벤트), `/dlc` (채팅) 명령어
- **ViragDevTool**: 인게임 디버거, 이벤트 레지스터, 변수 감시
- **EventTracker**: 이벤트 상세 정보 뷰어
- **Blizzard 내장**: `/eventtrace` — 이벤트 로그 창
- WeakAuras: 내장 로거 없음 (커뮤니티 기능 요청 상태)

### 현재 HealGuide
- `DEBUG = false` 플래그 (Init.lua:4) → `addon.dprint()` 가 메시지 출력
- 런타임 토글 불가 (파일 수정 + `/reload` 필요)
- 로그 저장 안 됨 → 기록이 사라짐
- 최근 알림 이력 조회 불가

### Gap
- (中) 사용자가 "방금 뭐가 뜬 거지?" 를 확인할 방법 없음
- (中) 문제 보고 시 재현 정보 수집 어려움
- (小) 개발자 본인(나중의 나)이 새 기능 디버깅 시 번거로움

### 구현 방향
- Storage 에 `debug = false` 필드 추가
- `/hg debug on|off` 슬래시 명령어 (런타임 토글)
- Storage 에 `recentEvents = {}` 링버퍼(최대 100개)
- `EncounterEngine`, `ImportParser`, `AlertFrame` 주요 지점에서 `addon:Log(category, msg)` 호출
- 설정 탭에 "디버그" 탭(또는 섹션):
  - 토글 체크박스
  - 최근 이벤트 스크롤 리스트 (시간/카테고리/메시지)
  - "로그 복사" 버튼 (EditBox 에 text 넣어서 Ctrl+C)
- `/hg dump` — HealGuideCharDB 핵심 내용을 채팅으로 출력 (문제 제보용)

### 난이도/가치
- 난이도: **중** (링버퍼 + 스크롤 리스트 UI)
- 가치: **중-높음** (QA 비용 절감, 사용자 문제 자가 해결)

---

## 보너스 항목 (요청 목록 외, 관련성 높음)

### Ace3 라이브러리 통합 전반
- **배경**: 거의 모든 메이저 애드온이 Ace3 생태계 사용 (AceDB/AceConfig/AceLocale/AceAddon/AceEvent/AceConsole)
- **이점**: 프로파일(AceDB), 선언적 설정 UI(AceConfig), 다국어(AceLocale), 이벤트 등록(AceEvent), 슬래시 파싱(AceConsole)
- **비용**: Libs/ 폴더 ~500KB 추가, 학습 곡선, 현재 순정 WoW API 구조 재작성
- **대안**: 순정 유지 + 필요한 라이브러리만 개별 편입(LSM, LibDualSpec)
- **결정 필요**: Ace3 올인 / 부분 편입 / 순정 유지. **제 추천은 부분 편입** (LibDualSpec, LibSharedMedia 만)

### Blizzard Options 패널 통합
- `InterfaceOptions_AddCategory` (deprecated) 또는 `Settings.RegisterCanvasLayoutCategory` (TWW 11.x 신 API)
- Esc → 인터페이스 → 애드온 탭에서 HealGuide 클릭 → 기본 설정창 열림
- 구현: MainFrame 을 Settings category 로 등록
- 가치: 발견성 ↑, 전문성 인상 ↑
- 난이도: **하**

### 로컬라이제이션 (i18n)
- 현재: 모든 UI 문자열 한국어 하드코드
- 업계 표준: AceLocale-3.0 또는 순정 방식
- 구조:
  ```lua
  local L = {}
  L["알림 위치"] = "알림 위치"  -- 기본: 한국어
  -- 다른 로케일 파일에서 L["알림 위치"] = "Alert Position"
  ```
- **현재 한국 사용자 전용이라면 후순위**. 영어 배포 고려 시점에 추가

### 자동 업데이트 감지
- `.toc` 의 `## Version` 과 SavedVariables 에 저장된 버전 비교
- 버전 상승 시 "업데이트됨: X.Y.Z" 토스트 + 변경사항 요약
- CurseForge/Wago 배포 시 유용

### Wago/Import 문자열 생태계
- WeakAuras 는 Wago.io 와 통합: `/wa import <url>` 로 커뮤니티 공유 aura 다운로드
- HealGuide 도 향후 커뮤니티가 import 문자열 공유하게 되면 Wago-like 저장소 필요할 수 있음
- **현재는 Mac 앱이 단일 생성 경로라 후순위**

---

## 우선순위 종합 매트릭스

| 항목 | 난이도 | 가치 | 우선순위 |
|---|---|---|---|
| 1. AceDB 프로파일 시스템 | 중 | 高 | **P1** |
| 4. 테마/색상 (LSM 통합) | 중 | 高 | **P1** |
| 6. 사운드 옵션 (LSM 통합) | 중 | 高 | **P1** (4 와 묶음) |
| 2. 프리셋/템플릿 | 하 | 중 | **P2** |
| 3. 키바인드 (토글만) | 하 | 중 | **P2** |
| 5. 조건부 표시 | 하-중 | 중 | **P2** |
| 8. 디버그/로깅 | 중 | 중-高 | **P2** |
| 7. 프레임 세부조정 | 하 | 중 | **P3** |
| (보너스) Blizzard Options 등록 | 하 | 중 | **P2** |
| (보너스) 자동 업데이트 감지 | 하 | 소 | **P3** |
| (보너스) i18n | 중 | 소 (한국 전용이면) | **P4** |
| (보너스) Ace3 올인 | 高 | 중 (장기) | **P4** |

### 추천 진행 순서 (마일스톤)

**Phase 4a — 프로파일 + 미디어 (2~3일 작업량)**
- AceDB-3.0 + LibDualSpec + LibSharedMedia 편입
- 프로파일 UI (드롭다운/복사/삭제/리셋)
- 사운드/폰트/색상 설정 UI
- Storage 마이그레이션 (HealGuideCharDB → AceDB 구조)

**Phase 4b — 프리셋 + 조건 + 키바인드 + Blizz Options (1~2일)**
- Presets.lua 정적 데이터 + 설정 UI
- 조건부 로딩 (PvP off 등)
- BINDING_* 글로벌 등록 + .xml
- Settings.RegisterCanvasLayoutCategory 로 Blizzard Options 등록

**Phase 4c — 디버그 뷰어 + 프레임 세부조정 (1~2일)**
- `/hg debug` 토글 + 링버퍼 + 설정 탭 신규 "디버그" 탭
- 프레임 스케일/투명도/스트라타/앵커 확장

**Phase 5 (장기) — 학습 기능 (아래 별도 장 참조), i18n, Wago 연계, 자동 업데이트**

---

## 결정이 필요한 선택지

1. **Ace3 올인 vs 부분 편입 vs 순정 유지**
   - 올인: 장기적으로 가장 유지보수 쉬움, 단기 재작성 비용 큼
   - 부분 편입 (LibSharedMedia + LibDualSpec): 실리적, 제 추천
   - 순정 유지: 자체 프로파일 시스템 구현, 학습 비용 최소

2. **Storage 스키마 호환성**
   - AceDB 도입 시 기존 `HealGuideCharDB` → `HealGuideDB.profiles[default]` 로 이전
   - 마이그레이션 코드 필수 (현재 유저가 없다면 간단, 있으면 신중)

3. **이 문서를 집 맥미니에서 어떻게 쓸 것인가**
   - Phase 4a 부터 즉시 착수할지, 인게임 실기 테스트 먼저 완료하고 착수할지
   - **제 추천**: 실기 테스트 → 현재 구현의 실제 취약점 확인 → 그 결과를 반영해서 Phase 4 우선순위 조정. 이 문서는 참고용 로드맵으로 활용

---

---

## Phase 5 — 학습 기능 설계

작성일: 2026-04-20
리서치 방식: WoW API 문서 직접 조사 + Details!/BigWigs GitHub 코드 분석 + 서브에이전트 domain-researcher 활용

### 요약

애드온 자체 학습 기능은 크게 5가지 후보로 나뉜다. 현재 `EncounterEngine.combatLog` 와 `CombatHistoryFrame` 으로 기초 인프라(전투 기록 + 이력 표시)가 이미 존재하므로, **신규 이벤트 구독 없이** 바로 확장 가능한 후보 B(가이드 이행률 추적)가 가장 낮은 공수로 즉각적인 가치를 제공한다. 그 다음 단계로 자기-로그 수집(A) → Delay 보정(C) 순으로 쌓는 것이 자연스러운 학습 파이프라인을 형성한다.

후보 D(미등록 보스 자동 경보)와 E(파티 힐러 분담)는 독립적인 인프라가 필요하고 신뢰도 리스크가 크므로 별도 Phase로 분리하거나 충분한 실기 데이터가 쌓인 이후에 착수하는 것이 안전하다.

---

### 후보 A — 자기-로그 자동 생성

> WarcraftLogs 없이 내 던전 플레이만으로 보스스킬→힐 패턴을 자동 축적한다.

#### 기술 아키텍처

**필요 이벤트:**
현재 `Init.lua` 에서 이미 구독 중:
- `COMBAT_LOG_EVENT_UNFILTERED` (clFrame) — 보스 `SPELL_CAST_START` 수신
- `SPELL_CAST_SUCCESS` with `UnitGUID("player")` — 플레이어 힐 캐스트 수신

추가 구독 없이 기존 `EncounterEngine.combatLog` 버퍼를 확장하면 된다.
현재 combatLog 스키마:
```lua
{ type="alert"|"used", spellID=N, source="reactive"|..., timestamp=T }
```

자기-로그 확장 스키마 (메모리 버퍼):
```lua
EncounterEngine._bossEventBuffer = {}
-- { bossSpellID=N, timestamp=T }   전투 중 임시 저장

-- SPELL_CAST_SUCCESS (hostile sourceFlags) 감지 시 push:
table.insert(EncounterEngine._bossEventBuffer,
    { bossSpellID = spellID, timestamp = GetTime() - encounterStartTime })

-- SPELL_CAST_SUCCESS (UnitGUID("player")) 감지 시:
-- _bossEventBuffer 를 역순 탐색 → 30초 이내 가장 최근 bossSpellID 찾기 → delay 계산
```

**저장 구조 (SavedVariables):**
```lua
HealGuideCharDB.selfLog = {
    -- [encounterID][bossSpellID][playerSpellID] = { count=N, mean=M, M2=V }
    -- Welford 알고리즘으로 점진 갱신 (O(spellPair 수) 고정 크기)
}
```

기존 `HGPT_Data` 와 병행 저장. 우선순위는 HGPT_Data 우선, selfLog 는 보완 데이터.

**성능:**
- 전투 중은 `_bossEventBuffer` 에 append만 (테이블 재할당 없음)
- 전투 종료 (`ENCOUNTER_END`) 시 `_bossEventBuffer` → Welford 갱신 → wipe(buffer)
- Welford 통계 업데이트: 곱셈/나눗셈 O(1), GC 없음

**taint 리스크:** 없음. 보호된 프레임 접근 없이 전투 로그만 읽음.

#### 패턴 감지 알고리즘

```
boss_cast_times = []  -- (bossSpellID, absTime) 전투 중 스택

for each player_cast (spellID, absTime):
    anchor = max { b ∈ boss_cast_times | b.absTime ≤ absTime }
    if anchor.absTime is nil: skip
    delay = absTime - anchor.absTime  (초)
    if delay > 30: skip
    updateWelford(selfLog[encID][anchor.bossSpellID][spellID], delay)
```

5회 이상 데이터가 쌓이면 통계적으로 신뢰할 수 있는 평균 delay 를 얻는다. Mac 앱 export 없이도 "내가 주로 X초에 Y를 쓴다"는 데이터 생성.

#### UX 플로우

- MainFrame **데이터 탭** 하단에 "자기-로그" 소섹션 추가
- 표시: 인카운터별 수집된 페어 수, 평균 delay 상위 5쌍
- "HGPT_Data 로 내보내기" 버튼: selfLog 집계값을 HGPT_Data 포맷으로 변환 → Mac 앱 없이 자체 가이드 생성 가능
- Mac 앱과 공존 시 우선순위 규칙: `HGPT_Data` 먼저, selfLog 는 HGPT_Data 에 없는 (encounterID, bossSpellID) 쌍에만 fallback

#### 리스크

| 리스크 | 내용 | 완화 |
|---|---|---|
| 콜드 스타트 | 첫 5회 이하에서 신뢰도 낮음 | `count < 5` 이면 UI 에 "데이터 부족" 표시, 알림 적용 비활성화 |
| 저품질 플레이 학습 | 느린 반응 → 큰 delay 가 평균을 끌어올림 | 표준편차 임계값 초과 시 "편차 큼" 경고 표시 |
| 보스 스킬 중복 매핑 | 같은 보스가 같은 스킬 20회 시전 → 모두 누적 | Welford 로 자동 평균화 됨. 의도된 동작 |
| SavedVariables 비대화 | (encounterID × bossSpellID × playerSpellID) 3중 키 | Welford 값만 저장 (3개 숫자/쌍), 100쌍 기준 ~3KB |

**우선순위 평가:**
- 구현 비용: 3/5 (bossEventBuffer 확장 + Welford 저장 + UI 소섹션)
- 사용자 가치: 4/5 (WarcraftLogs 없는 유저에게 핵심 기능)
- 제품 철학 적합도: 5/5 (자기 로그 자동화가 제품 핵심 가치와 직결)

---

### 후보 B — 가이드 이행률 추적

> 알림 뒤 실제 캐스트 여부·반응 속도를 추적하고, 놓친 알림을 피드백한다.

#### 기술 아키텍처

**기존 인프라 활용:**
`EncounterEngine.combatLog` 에 이미 `type="alert"` (알림 발화 시각)와 `type="used"` (플레이어 실제 캐스트 시각) 두 레코드가 쌓인다. `CombatHistoryFrame` 도 이미 `stats.fired` / `stats.used` 를 표시한다.

**확장 — 반응 속도 측정:**
```lua
-- TriggerAlert 내부에서 alert 기록 시 spellID → alertTime 매핑 저장
EncounterEngine._pendingAlerts = {}  -- [spellID] = alertTimestamp

-- OnPlayerCast 내부에서 매칭
local alertTime = EncounterEngine._pendingAlerts[spellID]
if alertTime then
    local reactionTime = GetTime() - alertTime  -- 알림→시전 소요 초
    EncounterEngine._pendingAlerts[spellID] = nil
    -- Welford 로 reactionTime 누적
end
```

**저장 구조:**
```lua
HealGuideCharDB.adherenceStats = {
    -- [encounterID][playerSpellID] = {
    --   alertCount = N,        -- 알림 발화 횟수
    --   usedCount  = N,        -- 실제 시전 횟수
    --   missedCount = N,       -- 반응 없이 윈도우(5초) 초과
    --   reactionTime = { count, mean, M2 },  -- 반응 속도 Welford
    -- }
}
```

**성능:** 전투 중 `_pendingAlerts` 는 해시 테이블 조회(O(1)). 전투 종료 후 만료된 pendingAlert 정리(5초 미응답 → missedCount 증가, C_Timer 이용).

**taint 리스크:** 없음.

#### 패턴 감지 알고리즘

```
window = 5초  -- 알림 후 이 시간 이내 캐스트 = "이행"
              -- 초과하면 "놓침"

C_Timer.NewTimer(window, function()
    if _pendingAlerts[spellID] still exists:
        adherenceStats.missedCount += 1
        _pendingAlerts[spellID] = nil
end)
```

이행률(%) = usedCount / alertCount × 100. 반응 시간 분포의 평균/표준편차로 "빠른 응답자"/"느린 응답자" 자가 진단 가능.

#### UX 플로우

- `CombatHistoryFrame` 을 확장: 기존 "알림 N 사용 N 적중 N%" 옆에 "반응 M.Ms" 컬럼 추가
- MainFrame **설정 탭** 에 "이행률 통계" 버튼 → 스펙별/던전별 장기 이행률 차트(간단한 텍스트 막대)
- 이행률 60% 미만 인카운터에 빨간 색상 강조
- `/hg adherence` 슬래시 명령어: 최근 10회 전투 이행률 요약 채팅 출력

#### 리스크

| 리스크 | 내용 | 완화 |
|---|---|---|
| 쿨다운으로 인한 미이행 | 스킬이 쿨다운 중이라 못 썼는데 "놓침"으로 집계 | `GetSpellCooldown` 으로 쿨다운 중 알림은 카운트에서 제외 (이미 `cooldownSkipped` 로 스킵됨, 이중 카운트 방지 필요) |
| 다른 힐로 대응 | 알림과 다른 힐을 써서 대처했는데 "놓침"으로 집계 | 5초 윈도우 내 **어떤** 힐 스킬이든 시전하면 "이행"으로 간주하는 넓은 모드 옵션 |
| 판타지 vs 실제 | 알림 자체가 잘못된 경우 이행률이 낮게 나옴 | selfLog(A)와 비교해서 알림의 품질과 이행률을 함께 평가 가능 |

**우선순위 평가:**
- 구현 비용: 2/5 (기존 combatLog 확장, 신규 이벤트 없음)
- 사용자 가치: 4/5 (자기 피드백 루프, 실력 향상 동기 부여)
- 제품 철학 적합도: 5/5 (가이드 시스템의 "효과 측정" 자연스러운 확장)

---

### 후보 C — Delay 자동 보정

> 같은 보스스킬에 대한 실제 내 반응 delay 분포를 학습해, 개인화된 리드타임을 자동 추천한다.

#### 기술 아키텍처

후보 A 의 `selfLog` 가 전제조건. `selfLog[encID][bossSpellID][playerSpellID].mean` 이 내 실제 평균 반응 delay. HGPT_Data 의 레퍼런스 delay 와 비교해 개인 오프셋(offset)을 계산한다.

**저장 구조 (selfLog 확장):**
```lua
HealGuideCharDB.selfLog = {
    [encounterID] = {
        [bossSpellID] = {
            [playerSpellID] = {
                count = N,
                mean  = M,   -- 내 평균 실제 반응 delay (초)
                M2    = V,   -- 분산 계산용 (Welford)
                refDelay = R -- import 시점의 HGPT_Data delay (스냅샷)
            }
        }
    }
}
```

**보정 계산:**
```lua
-- 권장 개인 오프셋 = 내 mean - refDelay
-- 양수: 나는 레퍼런스보다 느리게 반응 → leadTime 을 더 키워야 함
-- 음수: 나는 레퍼런스보다 빠르게 반응 → leadTime 을 줄여도 됨

local function computePersonalOffset(encID, bossSpellID, playerSpellID)
    local entry = HealGuideCharDB.selfLog[encID][bossSpellID][playerSpellID]
    if not entry or entry.count < 5 then return nil end
    return entry.mean - (entry.refDelay or 0)
end
```

**적용:** 전체 leadTime 설정 대신 스킬별 `entry.delay` 에 개인 오프셋 반영. 또는 "권장 leadTime 조정" 토스트 메시지로 사용자 안내.

**성능:** 계산은 `ENCOUNTER_END` 시 일괄 수행. 전투 중 추가 부하 없음.

#### 패턴 감지 알고리즘

5회 이상 데이터가 쌓인 (encounterID, bossSpellID, playerSpellID) 트리플에 대해:
```
personalOffset = mean(selfLog) - mean(HGPT_Data)
confidence = 1 / (1 + stddev/mean)  -- 변동계수 역수, 0~1
if confidence > 0.7 and |personalOffset| > 0.5초:
    → 보정 추천 대상
```

#### UX 플로우

- MainFrame **설정 탭** 에 "개인화" 섹션 추가
- "자동 분석" 버튼: 충분한 데이터(≥5회)가 쌓인 스킬에 대해 권장 보정값 목록 표시
  ```
  [거미여왕 - 독 분사 → 야성의 성장] 현재 리드 0.5초 → 권장 1.2초 (오차 ±0.3초)
  ```
- "모두 적용" / "개별 선택" / "무시" 버튼
- 적용 시 해당 entry 의 delay 값을 `HGPT_Data` 기준이 아닌 개인 보정값으로 저장

Mac 앱 HGPT_Data 와 공존: 재import 시 refDelay 스냅샷을 업데이트 → 개인 오프셋 재계산.

#### 리스크

| 리스크 | 내용 | 완화 |
|---|---|---|
| 저품질 플레이 학습 | 느린 반응→큰 delay 가 "정상"으로 학습됨 | stddev > mean × 0.5 이면 "불안정한 패턴" 경고, 적용 비권장 |
| 메타 패치 후 stale | 알림 타이밍이 바뀌었는데 개인 오프셋이 구버전 기준 | re-import 시 refDelay 스냅샷 갱신 + "개인 보정값 리셋" 버튼 |
| 후보 A 없이는 동작 불가 | selfLog 데이터 없으면 계산 불가 | A 완료 후 착수. UI 에 "자기-로그 데이터 필요" 안내 |

**우선순위 평가:**
- 구현 비용: 2/5 (A 완료 후 계산 레이어만 추가)
- 사용자 가치: 3/5 (파워 유저에게 매력적, 일반 유저는 관심 낮을 수 있음)
- 제품 철학 적합도: 4/5 (개인화 학습이 장기 가치를 높임)

---

### 후보 D — 미등록 보스 자동 경보

> 가이드 데이터가 없는 인카운터에서 보스의 상위 피해 스킬을 자동 감지해 임시 알림을 생성한다.

#### 기술 아키텍처

**필요 이벤트:**
```lua
-- ENCOUNTER_START 에서 encounterID 가 Storage 에 없는 경우 감지
if not addon.Storage:GetEncounterData(encounterID) then
    EncounterEngine:StartUnknownBossCapture(encounterID, encounterName)
end

-- COMBAT_LOG_EVENT_UNFILTERED 에서 SPELL_DAMAGE 추가 수신
-- (현재는 SPELL_CAST_START/SUCCESS 만 수신)
if subevent == "SPELL_DAMAGE"
   and bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
   and bossGUIDs[sourceGUID] then
    local spellID = select(12, CombatLogGetCurrentEventInfo())
    local amount  = select(15, CombatLogGetCurrentEventInfo())
    unknownBossLog[spellID] = (unknownBossLog[spellID] or 0) + amount
end
```

**보스 GUID 추적:**
```lua
-- ENCOUNTER_START 직후 boss1~boss5 유닛 GUID 캐싱
EncounterEngine.bossGUIDs = {}
for i = 1, 5 do
    local guid = UnitGUID("boss" .. i)
    if guid then EncounterEngine.bossGUIDs[guid] = true end
end
```

**저장 구조 (전투 중 임시, SavedVariables 미저장):**
```lua
EncounterEngine._unknownBossCapture = {
    encounterID   = N,
    encounterName = "...",
    spellDamage   = {},  -- [bossSpellID] = totalDamage
    spellCount    = {},  -- [bossSpellID] = castCount
}
```

전투 종료 후 상위 5개 스킬 추출 → SavedVariables 에 "후보 목록"으로 저장 → UI 에서 사용자가 확인/등록 결정.

**성능:**
- `SPELL_DAMAGE` 는 CLEU 에서 가장 빈번한 이벤트. bossGUIDs 해시 조회 + 누적만 수행 → O(1).
- 미등록 인카운터에서만 활성화 (`StartUnknownBossCapture` 플래그). 일반 전투에서 추가 부하 없음.

**taint 리스크:** 없음.

#### 패턴 감지 알고리즘

```
전투 종료 후:
candidateSpells = sort(spellDamage, descending)[1..N]

필터:
  - 피해량 상위 N=5
  - castCount >= 2 (1회 시전 스킬은 즉발 페이즈 기믹일 수 있음)
  - 이미 HGPT_Data 에 등록된 spellID 는 제외

→ unknownBossDB[encounterID] = candidateSpells 저장
```

#### UX 플로우

1. 전투 종료 후 미등록 인카운터면 채팅에 토스트:
   ```
   [HG] 미등록 인카운터 "거미여왕" 감지. 상위 스킬 5개 수집됨. /hg unknown 으로 확인
   ```
2. `/hg unknown` 명령어 또는 MainFrame 탭 → 수집된 스킬 목록 표시:
   - 스킬 아이콘 + 이름 + 피해량 + 시전 횟수
   - "반응 스킬" 필드 입력(옵션) + "등록" 버튼 → 임시 HGPT_Data entry 생성
3. 등록 시 반응 스킬 없이 "모니터 전용"으로도 등록 가능 (보스 스킬 시전 시 아이콘만 표시)

Mac 앱 HGPT_Data 와 공존: 임시 entry 는 `source="selfCapture"` 플래그. 이후 Mac 앱 정식 import 시 덮어씀.

#### 리스크

| 리스크 | 내용 | 완화 |
|---|---|---|
| 오탐(false positive) | 풀몹 광역 피해가 "보스 스킬"로 잡힘 | `bossGUIDs` 로 정확한 보스 GUID 필터링. 풀몹은 boss1~boss5 GUID 에 없음 |
| 기믹 스킬 노출 | 보스 즉발 페이즈 전환 스킬이 상위에 잡힘 | `castCount < 2` 필터로 1회성 제외 |
| SPELL_DAMAGE 추가 부하 | 미등록 인카운터에서만 활성화이지만 다인 레이드에서 SPELL_DAMAGE 폭증 | 보스 GUID 필터가 첫 번째 체크, 전체 이벤트의 5~10%만 통과 예상 |

**우선순위 평가:**
- 구현 비용: 3/5 (SPELL_DAMAGE 감지 + 미등록 분기 + UI)
- 사용자 가치: 3/5 (새 던전 패치 직후 대기 시간 단축에 유용)
- 제품 철학 적합도: 3/5 (자동화 가치 있으나 오탐 리스크가 제품 신뢰도를 훼손할 수 있음)

---

### 후보 E — 파티 힐러 분담 감지

> 같은 파티의 다른 힐러가 쿨다운을 방금 사용했으면, 중복 알림을 억제한다.

#### 기술 아키텍처

**필요 이벤트:**
이미 `COMBAT_LOG_EVENT_UNFILTERED` 를 구독 중. `SPELL_CAST_SUCCESS` 에서 파티원 힐러의 쿨다운 시전을 추가 감지한다.

```lua
-- Init.lua onCombatLog 에 추가 분기:
if subevent == "SPELL_CAST_SUCCESS"
   and sourceGUID ~= UnitGUID("player")
   and bit.band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY) ~= 0
   and bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then
    addon.EncounterEngine:OnPartyHealerCast(sourceGUID, spellID)
end
```

**파티 힐러 역할 판별:**
```lua
-- UnitGroupRolesAssigned: 던전파인더 그룹에서 신뢰도 높음
-- party1~party4 유닛 토큰 순회
local function buildHealerGUIDSet()
    local healerGUIDs = {}
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and "raid"..i or "party"..i
        if UnitGroupRolesAssigned(unit) == "HEALER" then
            local guid = UnitGUID(unit)
            if guid then healerGUIDs[guid] = true end
        end
    end
    return healerGUIDs
end
```

PLAYER_ROLES_ASSIGNED 이벤트로 역할 변경 시 healerGUIDSet 재빌드.

**파티원 쿨다운 추적:**
```lua
EncounterEngine.partyHealerCooldowns = {}
-- [spellID] = { guid = "...", usedAt = GetTime() }

function EncounterEngine:OnPartyHealerCast(sourceGUID, spellID)
    if not self.healerGUIDs or not self.healerGUIDs[sourceGUID] then return end
    if not MAJOR_HEALER_COOLDOWNS[spellID] then return end  -- 화이트리스트
    self.partyHealerCooldowns[spellID] = {
        guid   = sourceGUID,
        usedAt = GetTime(),
    }
    addon.dprint(string.format("[HG-Party] 힐러 %s 쿨다운 사용: %d", sourceGUID, spellID))
end
```

**TriggerAlert 억제 통합:**
```lua
-- TriggerAlert 내부 (쿨다운 스킵 로직 뒤)에 추가:
local partyCast = self.partyHealerCooldowns[spellID]
if partyCast then
    local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    local remaining = cd and (partyCast.usedAt + (cd.duration or 0) - GetTime()) or 0
    if remaining > 0 then
        self:_statInc("partySuppressionSkipped")
        addon.dprint("파티 힐러 중복 억제:", spellID)
        return
    end
end
```

**저장 구조:** partyHealerCooldowns 는 전투 중 메모리 테이블만. SavedVariables 저장 불필요.

**성능:** healerGUIDs 해시 조회 + MAJOR_HEALER_COOLDOWNS 화이트리스트 조회 → O(1). 화이트리스트에 없는 스킬은 즉시 탈출.

#### 패턴 감지 알고리즘

```
MAJOR_HEALER_COOLDOWNS = {
    -- 스펙 공통 대형 쿨다운만 포함 (소형 힐은 억제 대상 아님)
    [740]    = true,  -- Tranquility (Resto Druid)
    [267835] = true,  -- Velens Future Sight (Holy Priest)
    [62618]  = true,  -- Power Word: Barrier (Disc)
    [271466] = true,  -- Luminous Barrier (Disc)
    [208128] = true,  -- Apotheosis (Holy Paladin)
    [207399] = true,  -- Ancestral Protection Totem (Resto Shaman)
    [51052]  = true,  -- Anti-Magic Zone (DK)
    -- 확장 가능: SpecSpellCatalog 완성 후 연동
}

억제 조건:
  partyCast.usedAt + spellBaseCD > GetTime() + 3초 여유
  → "파티원이 아직 쿨다운 돌리는 중 → 내 알림 억제"
```

#### UX 플로우

- 설정 탭에 "파티 쿨 분담 억제" 체크박스 (기본 ON)
- 전투 요약 출력에 `partySuppressionSkipped` 카운터 추가:
  ```
  [HG] 전투 요약: 알림 8 | 파티 중복 억제 2 | ...
  ```
- 억제된 알림의 경우 AlertFrame 대신 미니맵 버튼 플래시 등 약한 시각 신호로 대체 가능 (옵션)

#### 리스크

| 리스크 | 내용 | 완화 |
|---|---|---|
| Blizzard API 제한 | 파티원의 실제 쿨다운 잔여 시간 조회 불가 (내 스킬만 GetSpellCooldown 신뢰 가능) | 파티원 시전 시각 + baseCD 계산 (추정). 부정확하면 ±5초 여유 버퍼 |
| 역할 미지정 그룹 | 수동 구성 파티에서 UnitGroupRolesAssigned == "NONE" | LibGroupInSpecT 편입 시 스펙 기반 힐러 판별 가능. 현재는 NONE 이면 추적 안 함 |
| 기능적 동등 스킬 | Tranquility ≡ Divine Hymn 이지만 spellID 가 다름 | MAJOR_HEALER_COOLDOWNS 에 스펙별 주요 쿨다운 모두 등록. SpecSpellCatalog 와 연동 (Phase 5 후반) |
| 5인 던전에서 힐러 1명 | 파티 힐러 추적 대상이 없음 → 이 기능 의미 없음 | 파티 힐러 2명 이상일 때만 활성화 |

**우선순위 평가:**
- 구현 비용: 3/5 (CLEU 파티 분기 + healerGUIDs 빌드 + 화이트리스트)
- 사용자 가치: 3/5 (힐러 2명 이상 파티 한정, 일반 M+ 5인은 힐러 1명)
- 제품 철학 적합도: 3/5 (레이드 환경에서 가치 높으나 주 대상인 M+ 에서는 적용 빈도 낮음)

---

### 우선순위 종합 매트릭스

| 후보 | 구현 비용 | 사용자 가치 | 제품 적합도 | 합산 | 착수 조건 |
|---|---|---|---|---|---|
| **B. 이행률 추적** | 2 | 4 | 5 | **11** | 즉시 (기존 인프라 확장) |
| **A. 자기-로그 생성** | 3 | 4 | 5 | **12** | 즉시 (신규 이벤트 불필요) |
| **C. Delay 자동 보정** | 2 | 3 | 4 | **9** | A 완료 후 |
| **D. 미등록 보스 경보** | 3 | 3 | 3 | **9** | 별도 (신뢰도 리스크 높음) |
| **E. 파티 힐러 분담** | 3 | 3 | 3 | **9** | 레이드 확장 시 |

*주의: 합산이 낮아도 A > B 를 권장하는 이유는 A 가 B 의 품질(알림 relevance)을 높이는 기반 데이터를 제공하기 때문.*

---

### 권장 Phase 5a 선정 + 구현 범위

**Phase 5a — 자기-로그 + 이행률 추적 (3~4일 작업량)**

A 와 B 를 동시 착수하는 이유:
- 공통 인프라(`EncounterEngine.combatLog` 확장, Welford 유틸, `adherenceStats` 저장) 를 한 번에 설계
- B(이행률)가 즉시 눈에 보이는 UX 가치를 제공하면서, A(자기-로그)가 장기 데이터를 쌓는 구조
- `CombatHistoryFrame` 확장 한 곳에서 두 기능의 UI 를 모두 노출 가능

**5a 범위:**
1. `EncounterEngine._bossEventBuffer` 추가 + SPELL_CAST_START(hostile) 기록
2. `OnPlayerCast` 에서 bossEventBuffer 매칭 → Welford 업데이트 → `selfLog` 저장
3. `TriggerAlert` 에서 `_pendingAlerts[spellID] = GetTime()` 기록
4. `OnPlayerCast` 에서 reactionTime 계산 + missedAlert C_Timer
5. `HealGuideCharDB.selfLog` + `adherenceStats` 스키마 확정
6. `CombatHistoryFrame` 에 반응 시간 컬럼 + 이행률 컬럼 추가
7. `/hg selflog` 슬래시: encounterID 별 수집 현황 채팅 출력
8. `/hg adherence` 슬래시: 최근 10회 이행률 요약 채팅 출력

**Phase 5b — Delay 자동 보정 (1~2일)**
5a 완료 + 5회 이상 데이터 축적 후 착수.

**Phase 5c — 미등록 보스 감지 (2일, 별도)**
패치 직후 실기 환경이 갖춰진 시점에 착수.

**Phase 5d — 파티 힐러 분담 (1~2일)**
레이드 테스트 환경이 마련됐을 때 착수. 5인 M+ 유저에게는 우선순위 낮음.

---

## 출처

리서치에 사용된 주요 출처:

- [WeakAuras2 GitHub Issues](https://github.com/WeakAuras/WeakAuras2/wiki) — 로드 조건 및 기능 명세
- [WeakAuras 조건 시스템 (DeepWiki)](https://deepwiki.com/WeakAuras/WeakAuras2/2.2-condition-system)
- [Wago.io](https://wago.io/) — WeakAuras/프로파일 커뮤니티 배포
- [AceDB-3.0 API (WowAce)](https://www.wowace.com/projects/ace3/pages/api/ace-db-3-0)
- [AceDB-3.0 Tutorial (WowAce)](https://www.wowace.com/projects/ace3/pages/ace-db-3-0-tutorial)
- [LibDualSpec-1.0 (GitHub)](https://github.com/AdiAddons/LibDualSpec-1.0)
- [AceConfigDialog-3.0 API](https://www.wowace.com/projects/ace3/pages/api/ace-config-dialog-3-0)
- [Ace3 for Dummies (Warcraft Wiki)](https://warcraft.wiki.gg/wiki/Ace3_for_Dummies)
- [BigWigs Boss Mods Guide (Wowhead)](https://www.wowhead.com/guide/bigwigs-boss-mods-addon-guide-6097)
- [BigWigs Voice+ (CurseForge)](https://www.curseforge.com/wow/addons/bigwigs-voice)
- [LibSharedMedia-3.0 (CurseForge)](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)
- [SharedMedia 사용 가이드 (Tukui)](https://www.tukui.org/forum/viewtopic.php?t=1)
- [DebugLog (CurseForge)](https://www.curseforge.com/wow/addons/debuglog)
- [ViragDevTool (GitHub)](https://github.com/varren/ViragDevTool)
- [EventTracker (Wago Addons)](https://addons.wago.io/addons/eventtracker)
- [Unified Profile Manager (CurseForge)](https://www.curseforge.com/wow/addons/unified-profile-manager)
- [DBM-Profiles (CurseForge)](https://www.curseforge.com/wow/addons/dbm-profiles)
- [COMBAT_LOG_EVENT - Warcraft Wiki](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT)
- [UnitFlag 비트마스크 - Warcraft Wiki](https://warcraft.wiki.gg/wiki/UnitFlag)
- [API CombatLogGetCurrentEventInfo - Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_CombatLogGetCurrentEventInfo)
- [GUID 포맷 - Warcraft Wiki](https://warcraft.wiki.gg/wiki/GUID)
- [API UnitGroupRolesAssigned - Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_UnitGroupRolesAssigned)
- [API GetInspectSpecialization - Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetInspectSpecialization)
- [Details! parser.lua - GitHub](https://github.com/Tercioo/Details-Damage-Meter/blob/master/core/parser.lua)
- [BigWigsMods/BigWigs - GitHub](https://github.com/BigWigsMods/BigWigs)
- [LibGroupInSpecT - CurseForge](https://www.curseforge.com/wow/addons/libgroupinspect)
