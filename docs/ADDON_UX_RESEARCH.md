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

**Phase 5 (장기) — i18n, Wago 연계, 자동 업데이트**

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
