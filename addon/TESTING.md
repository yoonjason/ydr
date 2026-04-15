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
- DungeonMappings.lua 는 TWW 시즌1 기준 — 시즌 변경 시 갱신 필요
- `C_VoiceChat.GetTtsVoices()` 필드명(voiceID, name)은 Interface 110200 기준 가정; 실제 인게임 확인 필요
- UIRadioButtonTemplate 일부 클라이언트에서 누락 시 UICheckButtonTemplate 자동 fallback

## 문제 발생 시

1. `/console scriptErrors 1` 켜고 재현
2. `/reload` 후 에러 메시지 수집
3. `HealGuideCharDB.lua` 파일 내용 확인 (구조 손상 여부)
4. 관련 파일과 라인 번호로 이슈 정리
