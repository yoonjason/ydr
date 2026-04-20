# HealGuide 애드온 인게임 테스트 가이드

통합 탭창(데이터/설정/미리보기) + 펄스 애니메이션 반영 버전. 순서대로 따라가며 각 단계를 체크하세요.

## 0. 사전 준비

1. WoW 설치 경로의 `Interface/AddOns/` 아래에 `addon/HealGuide/` 폴더를 복사 또는 심링크
   ```sh
   ln -s "$(pwd)/addon/HealGuide" "$HOME/Applications/World of Warcraft/_retail_/Interface/AddOns/HealGuide"
   ```
2. 와우 실행 → 캐릭터 선택 화면 **애드온** 버튼에서 HealGuide 체크
3. 힐러 스펙 캐릭터로 접속 (수양 사제 권장 — 테스트 데이터와 일치)
4. Mac 앱에서 테스트 URL 로 import 문자열 생성
   - URL: `https://www.warcraftlogs.com/reports/XqwA2yHChmM87GjR?fight=3&type=casts&source=143&view=timeline`
   - 4보스 M+ 던전, 수양 사제 데이터
   - "복사" 버튼으로 클립보드에 import 문자열 확보

## 1. 로드 확인 (Smoke test)

```
/hg
```

- [ ] `|cff00ff00HealGuide|r 로드 완료. /hg 로 설정` 메시지가 채팅창에 뜸
- [ ] **통합 탭창**이 열림 (데이터 탭이 기본 선택)
- [ ] 탭 버튼 3개: `데이터`, `설정`, `미리보기`
- [ ] Lua 에러 팝업이 **없음**

**에러 시**: `/console scriptErrors 1` 로 에러 표시 활성화 후 다시 로드.

## 2. 탭 전환

- [ ] **데이터** 탭 클릭 → 트리뷰 영역 표시
- [ ] **설정** 탭 클릭 → 설정 위젯 영역 표시
- [ ] **미리보기** 탭 클릭 → 테스트 버튼 영역 표시
- [ ] 탭 전환 시 Lua 에러 없음

## 3. Import 플로우

```
/hg import
```

- [ ] Import 다이얼로그가 열림
- [ ] 클립보드 문자열을 붙여넣기 (Cmd+V)
- [ ] "등록" 버튼 클릭 → 성공 메시지
- [ ] **데이터 탭** 트리뷰에 **던전 이름**이 추가됨
- [ ] 트리뷰 확장 시 **4개 보스** 노드가 보임
- [ ] 각 보스 아래 **DiscPriest** 스펙 엔트리
- [ ] EditBox 가 다이얼로그 너비 전체를 채움

### 보안 테스트 (ImportParser 샌드박스)

악성 페이로드를 `/hg import` 에 붙여넣어 거부되는지 확인:

1. **위험 패턴 거부**
   ```
   return os.execute("echo pwned")
   ```
   - [ ] "위험 패턴 감지" 에러 표시, 등록 실패

2. **for 루프 거부** (B4)
   ```
   return (function() for i=1,math.huge do end end)()
   ```
   - [ ] `for%s+` 패턴에서 거부

3. **빈 환경 탈출 시도**
   ```
   return (function() return _G end)()
   ```
   - [ ] `function(` 패턴에서 거부

4. **크기 상한** — 5MB 초과 문자열 붙여넣기 → [ ] "크기 초과" 에러

5. **잘못된 구조**
   ```
   return { foo = 1 }
   ```
   - [ ] version/bosses 검증 실패 메시지

6. **spellID 타입 검증** — timeline 항목에 `spellID = "not_a_number"` → [ ] 타입 오류

## 4. 데이터 탭 — 트리뷰 CRUD

데이터 탭에서:

- [ ] **이름 변경**: 던전 노드 이름변경 → 저장 반영 확인
- [ ] **토글 ON/OFF**: 클릭 → 상태 저장 확인 (재접속 후에도 유지)
- [ ] **갱신**: 같은 URL 을 다시 import → 기존 엔트리 덮어쓰기
- [ ] **삭제**: 삭제 버튼 → StaticPopup 확인 다이얼로그 → 트리뷰에서 사라짐
- [ ] **프레임 풀 (B3)**: Refresh 반복 호출 시 자식 프레임 누적 없음
- [ ] **'+ 새 던전 import' 버튼** → ImportDialog 열림

## 5. 설정 탭

설정 탭 클릭:

**알림 위치 그룹**
- [ ] **알림창 잠금** 체크박스: 클릭 시 locked 토글, 재접속 후 유지
- [ ] **위치 초기화** 버튼: AlertFrame 이 CENTER 0 200 으로 이동, 좌표 레이블 갱신
- [ ] **좌표 레이블**: 현재 alertFramePoint x,y 표시 (설정 탭 열 때 갱신)

**알림 크기 그룹**
- [ ] **기본 크기 슬라이더** (32-128): 드래그 → AlertFrame 아이콘 크기 실시간 반영
- [ ] **확대 크기 슬라이더** (48-160): 드래그 → 기본 크기 이상으로 자동 클램프
- [ ] 확대 크기 < 기본 크기 설정 불가 (자동 보정 확인)

**알림 표현 그룹**
- [ ] **사운드 재생** 체크박스: soundEnabled 토글
- [ ] **스킬명 표시** 체크박스: showSpellName 토글
- [ ] **TTS 읽기** 체크박스: ttsEnabled 토글 + TTS 세부 그룹 show/hide

**TTS 세부 그룹** (ttsEnabled=true 시 표시)
- [ ] **TTS 음성 선택** 버튼: 드롭다운 메뉴 표시, 선택 후 레이블 갱신
- [ ] **TTS 속도** 슬라이더: 값 저장 확인
- [ ] **TTS 볼륨** 슬라이더: 값 저장 확인
- [ ] ttsEnabled=false 시 TTS 세부 그룹 숨김

**알림 모드 그룹**
- [ ] reactive / absolute / hybrid 라디오 버튼: 하나만 체크됨
- [ ] 클릭 시 alertMode 갱신, 재접속 후 유지

## 6. 미리보기 탭

- [ ] **알림 테스트** 버튼: Power Word: Shield (spellID=17) 로 AlertFrame:ShowReminder 즉시 발동
- [ ] 알림 발동 시 **펄스 애니메이션** 확인 (아이콘 base → pulse → base)
- [ ] **encID 입력 + 시뮬레이션** 버튼: `3056` 입력 → EncounterEngine:TestEncounter(3056) 실행
- [ ] 올바른 encID 없으면 "encID를 입력하세요." 메시지

## 7. 알림 UI — 펄스 애니메이션

```
/hg size 64
/hg pulse 96
```

- [ ] 알림 발동 시 아이콘이 64px → 96px → 64px 으로 부드럽게 변화 (0.15초 + 0.35초)
- [ ] 위치(anchor)는 고정, 크기만 변경됨
- [ ] 펄스 도중 새 알림 오면 애니메이션 재시작 (spam 방지)
- [ ] 펄스 완료 후 페이드아웃은 기존 로직 유지

```
/hg pulse 48
```
- [ ] 확대 크기 = 기본 크기 (동일 시 펄스 없이 표시)

## 8. 슬래시 명령어 검증

```
/hg size 96
```
- [ ] iconBaseSize = 96, AlertFrame 아이콘 기본 크기 반영
- [ ] `/hg size 200` → 범위 초과 에러 메시지

```
/hg pulse 128
```
- [ ] iconPulseSize = 128
- [ ] `/hg pulse 32` (< base) → "기본 크기 이상" 에러 메시지

```
/hg lock
```
- [ ] 잠금 토글, 설정 탭 체크박스와 동기화
- [ ] 잠금 해제 상태: AlertFrame 드래그 가능, 위치 저장
- [ ] 잠금 상태: 드래그 불가

```
/hg mode reactive
/hg mode absolute
/hg mode hybrid
```
- [ ] 각 모드 전환 시 채팅 확인 메시지

```
/hg import
/hg test 3056
/hg sound off / on
/hg tts on / off
/hg label on / off
```
- [ ] 기존 명령어 모두 정상 동작

## 9. 시뮬레이션 테스트

```
/hg test 3056
```
- [ ] reactive 모드: 보스 스킬 감지 → 딜레이 후 알림
- [ ] absolute 모드: 절대 시간대 순차 알림
- [ ] hybrid 모드: 둘 다 발동, 1.5초 내 중복 디듀프
- [ ] **스펙 스왑 중 타이머 취소**: /hg test 후 스펙 변경 → 잔존 알림 없음 (B2 확인)

## 10. 알림 프레임 드래그/잠금

- [ ] 잠금 해제 상태: AlertFrame 드래그 가능
- [ ] 드래그 완료 시 좌표가 설정 탭 레이블에 즉시 반영
- [ ] HealGuideCharDB.settings.alertFramePoint 에 저장
- [ ] **위치 초기화** (설정 탭 버튼): CENTER 0 200 으로 복귀, 레이블 갱신
- [ ] 재접속 후 위치 복원

## 11. 실제 던전 진입

M+ 키스톤으로 해당 던전 진입:

- [ ] 던전 zone 진입 시 (optional) 토스트 메시지
- [ ] 전투 중에는 zone 토스트 미표시 (S4 확인)
- [ ] 첫 보스 pull → ENCOUNTER_START → EncounterEngine 자동 활성
- [ ] 보스 스킬 시전 → 알림 + 펄스 애니메이션
- [ ] ENCOUNTER_END 시 타이머 전부 취소

## 12. 스펙 스왑

- [ ] 힐러 → 다른 힐러: 스펙 데이터 swap, 알림 계속
- [ ] 힐러 → 비힐러: 알림 자동 OFF, 진행 중 타이머 취소 (B2)
- [ ] 비힐러 → 힐러: 알림 복귀

## 13. 구버전 iconSize 마이그레이션

기존 HealGuideCharDB.settings.iconSize 가 있는 캐릭터에서:

- [ ] 로드 시 iconSize 가 iconBaseSize 로 이전
- [ ] iconPulseSize = iconBaseSize * 1.5 (반올림) 로 자동 설정
- [ ] iconSize 키가 settings 에서 제거됨

## 14. 캐릭터별 독립 저장

- [ ] 캐릭터 A 에서 import 한 데이터가 캐릭터 B 에는 없음
- [ ] 같은 캐릭터의 여러 스펙 엔트리 공존
- [ ] HealGuideCharDB.settings 에 iconBaseSize, iconPulseSize 포함 확인

## 15. 고빈도 이벤트 스트레스

- [ ] 전투 중 CombatLog 초당 수백 이벤트 환경에서 프레임 드랍 없음
- [ ] 펄스 애니메이션 OnUpdate 부하 미미 (FPS 영향 없음)

## 16. 알려진 한계 / 주의사항

- 레이드 단일 보스 import 시 dungeonName 이 보스 이름으로 들어감
- DungeonMappings.lua 는 누적형 mapID→dungeonKey 테이블. 신규 M+ 던전 등장 시에만 추가. 시즌/확장팩 변경으로 재작성 불필요. ValidateActiveSeason 이 미등록 던전을 debug 로그로 고지.
- `C_VoiceChat.GetTtsVoices()` 필드명(voiceID, name)은 Interface 110200 기준 가정; 실제 인게임 확인 필요
- UIRadioButtonTemplate 일부 클라이언트에서 누락 시 UICheckButtonTemplate 자동 fallback

## 17. Phase 4a: AceDB 프로파일 + LibSharedMedia 테마

### 마이그레이션 검증

- [ ] 기존 `HealGuideCharDB` 데이터가 있는 캐릭터로 로그인
- [ ] `/reload` 후 던전 데이터·설정이 그대로 유지됨
- [ ] `HealGuideDB.profiles["<캐릭터명> - <서버명>"]` 에 마이그레이션된 데이터 확인
- [ ] `db.profile._charDbMigrated == true` 플래그 존재 (2회 실행 방지)

### 프로파일 관리

설정 탭 → **프로파일** 섹션:

- [ ] "현재: `<프로파일명>`" 레이블이 올바른 현재 프로파일 표시
- [ ] **전환 ▾** 드롭다운: 다른 프로파일 목록 표시, 클릭 시 전환 + 레이블 갱신
- [ ] **새로 만들기**: 이름 입력 팝업 → 새 프로파일 생성 + 자동 전환
- [ ] **복사**: 새 이름 입력 팝업 → 현재 프로파일 데이터 복사 + 전환
- [ ] **삭제**: 다른 프로파일 드롭다운 → 확인 팝업 → 삭제
- [ ] **리셋**: 확인 팝업 → 현재 프로파일을 기본값으로 초기화
- [ ] 프로파일 전환 시 설정 탭·데이터 탭이 자동 갱신
- [ ] 프로파일 전환 시 AlertFrame·TimelineFrame 테마 즉시 반영
- [ ] 현재 활성 프로파일은 삭제 목록에서 제외 확인

### 테마 설정

설정 탭 → **테마** 섹션:

**사운드:**
- [ ] "사운드: ReadyCheck" 기본값 표시
- [ ] **선택 ▾** 드롭다운: LibSharedMedia 등록 사운드 목록 표시 (None / ReadyCheck / Alarm Clock 등)
- [ ] 선택 후 레이블 갱신
- [ ] **테스트** 버튼: 선택한 LSM 사운드 재생 (PlaySoundFile 경로)
- [ ] "None" 선택 시 사운드 미재생

**폰트:**
- [ ] "폰트: Friz Quadrata TT" 기본값 표시
- [ ] **선택 ▾** 드롭다운: LibSharedMedia 등록 폰트 목록 표시
- [ ] 선택 후 AlertFrame 알림 텍스트에 즉시 반영
- [ ] TimelineFrame 아이콘 시간 텍스트에도 즉시 반영

**폰트 크기 슬라이더 (8-24):**
- [ ] 드래그 시 AlertFrame·TimelineFrame 폰트 크기 즉시 반영

**배경 색상 (견본 버튼):**
- [ ] 클릭 시 ColorPickerFrame 열림 (불투명도 슬라이더 포함)
- [ ] 색상 변경 시 AlertFrame 슬롯 배경 즉시 갱신
- [ ] 취소 시 이전 색상으로 복구

**텍스트 색상 (견본 버튼):**
- [ ] 클릭 시 ColorPickerFrame 열림
- [ ] 색상 변경 시 AlertFrame nameText 즉시 갱신

### LibDualSpec 검증

- [ ] 스펙 전환 시 해당 스펙에 할당된 프로파일로 자동 스왑 (SetDualSpecProfile로 미리 설정 필요)
- [ ] `db.SetDualSpecProfile("프로파일명", 1)` → 스펙 1 전환 시 자동 스왑

### 인게임 확인 체크리스트

1. `/hg` 열기 → 설정 탭 → 프로파일 섹션 확인
2. 새 프로파일 "테스트" 생성 → 알림 크기 변경 → 원래 프로파일로 전환 → 크기 복구 확인
3. 테마 탭에서 배경색을 빨간색으로 변경 → 알림 테스트 → 빨간 배경 확인
4. 폰트를 "Arial Narrow"로 변경 → 알림 테스트 → 폰트 변경 확인
5. 사운드를 "Alarm Clock"으로 변경 → 테스트 버튼 → 다른 소리 확인
6. `/reload` 후 모든 테마 설정 유지 확인

## §18 랭커 데이터 탭 (Phase 5α)

### 파일 로드 검증

- [ ] `/reload` 후 `HGPT_RankerData` 전역이 존재하는지 확인 (`/dump HGPT_RankerData`)
- [ ] `HGPT_RankerData.entries` 가 배열이고 `_meta` / `data` 필드를 가지는지 확인

### 탭 UI 검증

- [ ] `/hg` 열기 → '랭커 데이터' 탭 버튼이 네 번째로 표시됨
- [ ] 탭 클릭 시 패널 전환, 다른 탭 내용 숨겨짐
- [ ] 더미 데이터 존재 시 배너가 "데이터 최신 상태"(초록) 표시
- [ ] `HGPT_RankerData = nil` 로 덮어쓴 뒤 `/hg` → 탭에 "데이터 없음 — Mac 앱에서 수집하세요"(빨강) 표시
- [ ] `collectedAt` 을 15일 이전 날짜로 바꾼 더미 데이터 로드 → 배너가 "N일 경과 — 갱신 권장"(노랑) 표시

### 엔트리 목록 검증

- [ ] 더미 데이터 1개 엔트리가 목록에 행으로 표시됨
- [ ] 행 텍스트: 스펙 · 던전명 · 난이도 · 수집일 · 랭커 수 포함 확인
- [ ] ▶ 화살표 클릭 시 상세 펼치기, 재클릭 시 접힘
- [ ] 상세 펼침 시 컬럼 헤더(보스 스킬 / 힐 스킬 / delay / ±stddev / quorum) 표시
- [ ] 더미 데이터의 매핑 행(bossSpellID 440802 → spellID 33206, 47788)이 표시됨
- [ ] 여러 엔트리 동시 클릭 시 각 엔트리 독립적으로 동작

### 전체 토글 검증

- [ ] '랭커 데이터 적용' 체크박스 ON → `Storage:GetSetting("useRankerData")` == true
- [ ] 체크박스 OFF → `Storage:GetSetting("useRankerData")` == false
- [ ] `/reload` 후 체크박스 상태 유지 (AceDB 영속화 확인)

### 레이어드 조회 검증

- [ ] 더미 데이터의 bossSpellID(440802)가 매핑된 encounterID로 `OnCombatLog` 시뮬레이션 시
  랭커 데이터 경로로 알림 발화 확인 (debugMode ON, `[HG-CL]` 로그 확인)
- [ ] `useRankerData = false` 설정 후 동일 조건에서 `activeSpecData.reactions` 경로로 fallback 확인
- [ ] 랭커 데이터에 없는 bossSpellID는 기존 reactions 경로로 정상 처리 확인
- [ ] `HGPT_RankerData = nil` 상태에서도 기존 알림 기능 완전 정상 동작

### 기존 기능 무영향 확인

- [ ] 데이터 탭, 설정 탭, 미리보기 탭 기능 모두 정상 동작
- [ ] AlertFrame / TimelineFrame / MinimapButton 무영향
- [ ] 레이드/M+ 인카운터 시작/종료 정상 처리
- [ ] `/reload` 후 AceDB 프로파일 설정 전체 유지

## 문제 발생 시

1. `/console scriptErrors 1` 켜고 재현
2. `/reload` 후 에러 메시지 수집
3. `HealGuideDB.lua` 또는 `HealGuideCharDB.lua` 파일 내용 확인 (구조 손상 여부)
4. 관련 파일과 라인 번호로 이슈 정리
