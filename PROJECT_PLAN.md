# WoW 힐링 가이드 시스템 — PROJECT_PLAN

## 1. 개요

### 한 줄 설명
**"고수 힐러 로그를 앱이 읽어서 '언제 무슨 힐을 써야 하는지' 데이터로 뽑아주고, 인게임 애드온이 그 데이터로 전투 중 실시간 알림을 띄운다."**

### 전체 흐름
```
[WarcraftLogs URL] → [맥 앱이 API 호출 + 분석] → [Lua 데이터 문자열]
                                                      │
                                                      ▼
                                              [Data.lua 에 붙여넣기]
                                                      │
                                                      ▼
[쐐기 던전 진행 중] → [보스 X 스킬 감지] → [N초 뒤 힐 Y 써!] 알림
```

두 개의 독립적인 프로젝트로 구성된 WoW 힐링 가이드 시스템.

1. **macOS 네이티브 앱** (SwiftUI) — WarcraftLogs 로그에서 힐러의 치유 타임라인을 추출해 와우 애드온용 Lua 데이터로 변환
2. **와우 인게임 애드온** (Lua) — 앱이 생성한 Lua 데이터를 로드해서, 전투 중 보스가 특정 스킬을 시전할 때 플레이어에게 어떤 힐 스킬을 써야 하는지 실시간으로 알림

**대상 스펙**: 와우 라이브 버전의 모든 힐러 스펙 (6개 클래스, 7개 스펙)

| 클래스 | 스펙 | 표기 키 (Data.lua) |
|-------|------|-----------------|
| Priest | Discipline | `DiscPriest` |
| Priest | Holy | `HolyPriest` |
| Druid | Restoration | `RestoDruid` |
| Monk | Mistweaver | `MistweaverMonk` |
| Paladin | Holy | `HolyPaladin` |
| Shaman | Restoration | `RestoShaman` |
| Evoker | Preservation | `PresEvoker` |

---

## 2. 핵심 가치 제안 (Why)

- **고수 로그 학습 자동화**: 상위 파스 로그를 보면서 "이 보스 스킬 이후 몇 초에 무슨 힐을 썼나" 를 수동 정리하는 시간을 0으로 만든다
- **인게임 실시간 가이드**: 쐐기 던전 진행 중 보스 스킬에 맞춰 적절한 힐 쿨을 자동으로 큐잉
- **다 스펙 공유 가능**: 친구나 공팟 힐러와 가이드 데이터를 공유하기 쉬운 JSON/Lua 포맷

---

## 3. 프로젝트 구조

```
ydr/
├── README.md
├── CLAUDE.md
├── PROJECT_PLAN.md          ← 본 문서
├── .gitignore
├── app/                      ← 프로젝트 1: SwiftUI macOS 앱
│   ├── project.yml           ← XcodeGen
│   ├── HealGuide/
│   │   ├── App/              ← 진입점, AppDelegate
│   │   ├── Models/           ← 데이터 모델 (Report, Fight, Event, Spec 등)
│   │   ├── Services/         ← WarcraftLogs API 클라이언트, 타임라인 정규화, Lua 생성기
│   │   ├── ViewModels/
│   │   ├── Views/            ← ContentView, 입력폼, 결과 텍스트뷰
│   │   └── Info.plist
│   └── HealGuideTests/
└── addon/                    ← 프로젝트 2: 와우 인게임 애드온
    ├── HealGuide.toc
    ├── Main.lua              ← 이벤트 핸들링, 알림 표시
    └── Data.lua              ← 앱이 생성한 HGPT_Data 여기에 붙여넣기
```

---

## 4. Project 1: macOS 앱

### 4.1 UI 요구사항 (FR)

1. **입력 영역**
   - WarcraftLogs 로그 URL 입력 필드 (단일 행)
   - API Client ID 입력 필드
   - API Client Secret 입력 필드 (SecureField, Keychain에 자동 저장)
   - 최초 실행 시 Client ID/Secret 입력 안내
2. **액션**
   - **"데이터 가져오기"** 버튼
   - **"클립보드에 복사"** 버튼
3. **출력 영역**
   - 결과 Lua 문자열 (수직 스크롤 가능한 monospace 텍스트뷰)
   - 상태 메시지: fetching / parsing / error / done

### 4.2 비기능 요구사항 (NFR)

- **오프라인 저장**: Client ID/Secret 은 macOS Keychain 사용 (앱 삭제 후에도 유지 가능)
- **에러 메시지 명확화**: OAuth 실패 / URL 파싱 실패 / Rate limit 초과 / 힐러가 아닌 소스 선택 등 각각의 에러를 구분해서 표시
- **재시도 내성**: 네트워크 일시 오류에 대해 지수 백오프 1회 재시도
- **macOS 14 Sonoma+ 지원**

### 4.3 입력 URL 파싱

예시:
```
https://www.warcraftlogs.com/reports/AbCdEfGh12345678#fight=3&source=5
                                     └──────┬──────┘      └┬┘      └┬┘
                                        reportCode     fightID  sourceID
```

- `reportCode`: `/reports/` 다음의 `[A-Za-z0-9]+` 8~16자
- `fightID`: URL hash fragment 의 `fight=<number>` 또는 `fight=last`
- `sourceID`: URL hash fragment 의 `source=<number>` (플레이어 actor ID)

파싱 실패 시 사용자에게 "URL 형식이 올바르지 않습니다" 안내.

### 4.4 WarcraftLogs API 호출

**엔드포인트**: `https://www.warcraftlogs.com/api/v2/client`
**인증**: OAuth2 Client Credentials flow
  - Token 엔드포인트: `https://www.warcraftlogs.com/oauth/token`
  - `grant_type=client_credentials` + HTTP Basic Auth (`client_id:client_secret`)
  - 토큰 수명: 1시간, 메모리 캐싱 후 만료 시 재요청

**GraphQL 쿼리 예시** (fight 메타 + 플레이어 CastEvents):
```graphql
query($code: String!, $fightID: Int!, $sourceID: Int!) {
  reportData {
    report(code: $code) {
      fights(fightIDs: [$fightID]) {
        id
        startTime
        endTime
        name
        kill
      }
      events(
        fightIDs: [$fightID]
        sourceID: $sourceID
        dataType: Casts
        startTime: 0
        endTime: 9999999
      ) {
        data
        nextPageTimestamp
      }
    }
  }
}
```

**보스 CastEvents** 는 별도 쿼리:
```graphql
events(
  fightIDs: [$fightID]
  dataType: Casts
  hostilityType: Enemies
)
```

**페이지네이션**: `nextPageTimestamp` 가 null이 아니면 해당 값을 `startTime` 으로 넣어 재쿼리.

**응답 데이터 구조** (`events.data` 는 JSON string):
```json
[
  { "timestamp": 123456, "type": "cast", "sourceID": 5, "abilityGameID": 17 },
  ...
]
```

### 4.5 타임라인 정규화 알고리즘

**목표**: 각 플레이어 힐 캐스트가 "어떤 보스 스킬 시전 후 몇 초 뒤"에 발생했는지 계산.

**의사코드**:
```
bossCasts  = [ (time, abilityID) ] — 보스 CastEvents 정렬됨
playerCasts = [ (time, abilityID) ] — 플레이어 CastEvents 정렬됨

result = {}  // boss ability ID -> [ { spellID, delay } ]

for each p in playerCasts:
    // p.time 이전에 일어난 가장 최근 보스 캐스트 찾기
    anchor = last b in bossCasts where b.time <= p.time
    if anchor is nil:
        continue  // 보스 캐스트 전의 힐은 무시 (프리캐스팅 등)
    
    delay = (p.time - anchor.time) / 1000.0  // ms -> seconds
    if delay > MAX_WINDOW_SECONDS (예: 30초):
        continue  // 너무 떨어진 것은 연관 없다고 간주
    
    result[anchor.abilityID].append({ spellID: p.abilityID, delay: delay })

// 후처리: boss ability 별로 delay 기준 정렬
for key in result:
    result[key].sort(by: delay ascending)
```

**튜닝 파라미터**:
- `MAX_WINDOW_SECONDS` = 30초 (보스 캐스트 창)
- **반복되는 보스 스킬** (예: 주기적 쉴드) 처리: 현재는 각 인스턴스를 같은 key 로 묶어서 저장. 여러 시전 중 공통적으로 사용되는 힐만 필터링하는 로직은 Phase 2 에서 고려.

### 4.6 Lua 출력 포맷

```lua
-- 이 파일은 HealGuide macOS 앱으로 생성되었습니다.
-- 생성일: 2026-04-15T12:34:56+09:00
-- 원본 로그: https://www.warcraftlogs.com/reports/AbCdEfGh12345678#fight=3&source=5
-- 보스: 000번 던전 — 보스이름
-- 스펙: DiscPriest

HGPT_Data = HGPT_Data or {}
HGPT_Data["DiscPriest"] = HGPT_Data["DiscPriest"] or {}

HGPT_Data["DiscPriest"][<encounterID>] = {
  [<bossSpellID>] = {
    { spellID = 17,     delay = 0.5 },   -- Power Word: Shield
    { spellID = 33076,  delay = 2.3 },   -- Prayer of Mending
  },
  ...
}
```

**키 설계 원칙**:
- **스펙 이름**: 최상위 키 (스펙별로 독립 저장, 한 Data.lua 에 여러 스펙 공존 가능)
- **encounterID**: Blizzard 의 공식 encounter ID. 애드온이 `EncounterID` 를 통해 매칭
- **bossSpellID**: 숫자 (spell ID) — 현지화 안전
- **spellID**: 플레이어 힐 spell ID — 마찬가지로 현지화 안전
- **이름 주석**: `-- Power Word: Shield` 처럼 가독성을 위해 주석으로 병기

**Merge 친화적 출력**:
- 여러 보스 로그를 순차적으로 export 하면 `HGPT_Data["DiscPriest"][A] = ...; HGPT_Data["DiscPriest"][B] = ...` 식으로 **덮어쓰지 않고 추가**되도록 함
- 단, 동일 (spec, encounterID) 조합을 다시 export 하면 해당 블록은 덮어씀

### 4.7 데이터 모델 (Swift)

```swift
struct ReportURL {
    let code: String
    let fightID: Int
    let sourceID: Int
}

struct APICredentials {
    let clientID: String
    let clientSecret: String  // Keychain 저장
}

enum HealerSpec: String, CaseIterable, Identifiable {
    case discPriest    = "DiscPriest"
    case holyPriest    = "HolyPriest"
    case restoDruid    = "RestoDruid"
    case mistweaverMonk = "MistweaverMonk"
    case holyPaladin   = "HolyPaladin"
    case restoShaman   = "RestoShaman"
    case presEvoker    = "PresEvoker"

    var id: String { rawValue }
    var displayName: String { ... }
}

struct FightMeta {
    let id: Int
    let encounterID: Int
    let name: String
    let startTime: Int64  // ms epoch
    let endTime: Int64
    let kill: Bool
}

struct CastEvent {
    let timestamp: Int64   // ms epoch
    let sourceID: Int
    let abilityID: Int
}

struct TimelineEntry {
    let bossAbilityID: Int
    let playerSpellID: Int
    let delay: Double  // seconds
}
```

### 4.8 서비스 레이어 (프로토콜 지향 + 생성자 주입)

```swift
protocol KeychainStoring {
    func saveClientSecret(_ value: String) throws
    func loadClientSecret() -> String?
    func deleteClientSecret()
}

protocol WarcraftLogsAPIClient {
    func fetchAccessToken(credentials: APICredentials) async throws -> String
    func fetchFight(reportCode: String, fightID: Int, token: String) async throws -> FightMeta
    func fetchCasts(reportCode: String, fightID: Int, sourceID: Int?, isEnemy: Bool, token: String) async throws -> [CastEvent]
}

protocol TimelineNormalizer {
    func normalize(bossCasts: [CastEvent], playerCasts: [CastEvent], maxWindow: TimeInterval) -> [TimelineEntry]
}

protocol LuaGenerator {
    func generate(spec: HealerSpec, encounterID: Int, entries: [TimelineEntry], metadata: ExportMetadata) -> String
}
```

---

## 5. Project 2: WoW 애드온

### 5.1 파일 구조

```
HealGuide/                    <- 인게임에서 이 이름으로 인식
├── HealGuide.toc             <- 메타데이터
├── Main.lua                  <- 이벤트 핸들러, 알림 UI
└── Data.lua                  <- 앱이 생성한 HGPT_Data (자주 갱신)
```

### 5.2 .toc 파일

```toc
## Interface: 110200
## Title: HealGuide
## Notes: Boss skill-based healing reminder for healers
## Version: 0.1.0
## Author: yeongseok
## SavedVariables: HealGuideDB

Data.lua
Main.lua
```

**Interface 버전**은 릴리즈 당시 최신 라이브 버전으로 맞춰야 함. TWW 11.x 기준 `110200` 또는 그 이상.

### 5.3 동작 흐름

1. 애드온 로드 시 `Data.lua` 의 `HGPT_Data` 테이블을 전역으로 로드
2. `PLAYER_SPECIALIZATION_CHANGED` 이벤트로 현재 스펙 감지 → 해당 스펙 데이터만 활성화
3. `ENCOUNTER_START` 이벤트로 현재 encounterID 감지 → 해당 인카운터 데이터만 활성화
4. `COMBAT_LOG_EVENT_UNFILTERED` 리스닝
5. 이벤트 파라미터 분석:
   - `eventType == "SPELL_CAST_START"` or `"SPELL_CAST_SUCCESS"`
   - `sourceFlags` 에서 `COMBATLOG_OBJECT_REACTION_HOSTILE` 비트 체크 (보스 구분)
   - `spellID` 가 활성 데이터의 키에 존재하면 큐잉
6. 해당 스킬에 매핑된 `{spellID, delay}` 목록을 순회하며 `C_Timer.After(delay, function() showReminder(spellID) end)` 로 예약
7. **알림 UI**:
   - 화면 중앙 상단 근처에 `Frame` 생성 (드래그로 이동 가능)
   - 스킬 아이콘 (`GetSpellTexture(spellID)`) + 스킬 이름 (`GetSpellInfo(spellID)`)
   - 2초간 표시 후 fade out
   - 소리: `PlaySoundFile("Interface\\AddOns\\HealGuide\\alert.ogg", "Master")` 또는 기본 `PlaySound(888)` (raid warning)
8. `ENCOUNTER_END` 시 모든 대기 타이머 취소

### 5.4 상태 변수 (SavedVariables)

```lua
HealGuideDB = {
    enabled        = true,
    soundEnabled   = true,
    framePosition  = { x = 0, y = 200 },
    displaySeconds = 2.0,
}
```

### 5.5 슬래시 명령어

```lua
/hg           -- 설정 창 열기 (Phase 3)
/hg test      -- 알림 테스트
/hg lock      -- 프레임 위치 고정/해제
```

---

## 6. 구현 로드맵

### Phase 1 — 앱 MVP (하나의 로그, 하나의 스펙)
- [ ] Xcode 프로젝트 스켈레톤 + SwiftUI 기본 UI
- [ ] Keychain 래퍼 (Client Secret 저장/로드)
- [ ] WarcraftLogs OAuth2 클라이언트 (토큰 받기)
- [ ] URL 파서
- [ ] Fight 메타 fetch
- [ ] 플레이어 CastEvents fetch (단일 fight)
- [ ] 보스 CastEvents fetch
- [ ] TimelineNormalizer 기본 구현
- [ ] LuaGenerator 기본 구현 (spell ID 기반)
- [ ] 결과 텍스트뷰 + 클립보드 복사 버튼
- **DoD**: 실제 WarcraftLogs URL 입력 → 버튼 클릭 → 한 보스 블록이 들어간 Lua 문자열 생성 → 클립보드 복사 성공

### Phase 2 — 앱 품질 향상
- [ ] 여러 fight 에 걸친 export (전체 로그 export)
- [ ] 스펙 자동 감지 (로그에서 actor subType 기반)
- [ ] Merge-friendly 출력 (기존 Data.lua 와 병합 가능)
- [ ] 에러 메시지 국제화
- [ ] 단위 테스트: URL 파서, 타임라인 정규화, Lua 생성기
- **DoD**: 여러 로그를 export 해서 하나의 Data.lua 를 완성할 수 있음

### Phase 3 — 애드온 MVP (하나의 스펙, 하나의 인카운터)
- [ ] `.toc` + 파일 구조
- [ ] `Data.lua` 에 Phase 1 산출물 붙여넣기
- [ ] Main.lua: 이벤트 등록, 스펙 감지, encounterID 감지
- [ ] COMBAT_LOG 파싱 + 매칭
- [ ] 기본 알림 UI (스킬 아이콘 + 이름)
- [ ] 기본 소리 재생
- **DoD**: 테스트 서버 또는 훈련용 보스에서 실제 알림이 뜸

### Phase 4 — 애드온 품질 향상
- [ ] 프레임 드래그 이동 + 위치 저장
- [ ] 설정 창 (`/hg`)
- [ ] 인카운터 로드/언로드 최적화
- [ ] 시각 효과 개선 (페이드, 아이콘 테두리 등)
- **DoD**: 실전 쐐기 던전에서 깨짐 없이 동작

### Phase 5 — 풀 스펙 지원 + 배포 준비
- [ ] 7개 힐러 스펙 전부 테스트
- [ ] 앱 DMG 빌드 스크립트
- [ ] 애드온 패키징 (CurseForge / Wago 업로드 포맷)
- **DoD**: 친구에게 DMG + 애드온 zip 배포 가능

---

## 7. 오픈 이슈 (해결 필요)

- [ ] **인카운터 ID 매핑**: WarcraftLogs 는 자체 encounterID 를 쓸 수도 있음 — Blizzard encounterJournal ID 와 일치하는지 확인 필요
- [ ] **여러 힐러가 한 로그에 있을 때**: `source=5` 를 유저가 직접 골라야 하는데, 앱에서 actor 목록을 보여주고 선택하도록 UX 개선 필요 (Phase 2)
- [ ] **보스의 SPELL_CAST_SUCCESS vs SPELL_CAST_START**: 둘 다 로그에 찍힘. 어느 쪽을 "기준 시간" 으로 쓸지 결정 필요 — 일반적으로 START 가 더 "반응 시점" 에 적합
- [ ] **반복 보스 스킬의 평균/대표값 계산**: 같은 보스 스킬이 20번 시전됐을 때 매번의 힐 대응을 다 저장할지, 평균/대표값만 저장할지
- [ ] **프리핸드 힐러 사용량**: 상위 파스 로그만 fetch 하도록 할 건지, 사용자가 임의 로그 넣는 걸 허용할 건지
- [ ] **API Rate limit**: 점수제이므로 fetch 양이 많으면 재인증 필요

---

## 8. 기술 스택

| 영역 | 선택 |
|------|------|
| 앱 UI | SwiftUI (macOS 14+) |
| 앱 네트워킹 | `URLSession` + `async/await` |
| 앱 저장소 | Keychain (Secrets), `UserDefaults` (UI 상태) |
| 앱 아키텍처 | MVVM + 프로토콜 지향 DI |
| 앱 프로젝트 생성 | XcodeGen (`project.yml`) |
| 앱 테스트 | XCTest |
| 애드온 언어 | Lua 5.1 (WoW 런타임) |
| 애드온 API | Blizzard WoW API (COMBAT_LOG_EVENT_UNFILTERED, C_Timer, GetSpellInfo 등) |

---

## 9. 용어

- **Report**: WarcraftLogs 하나의 로그 (한 저녁의 공격대 전체 기록 등)
- **Fight**: Report 안의 한 전투 (보스 한 번 시도)
- **Source**: 로그 안의 actor (플레이어 캐릭터 또는 보스)
- **Ability**: 스킬. `abilityGameID` = Blizzard spellID
- **EncounterID**: Blizzard 가 공식적으로 부여한 보스 고유 ID
- **HGPT**: HealGuide Player Timeline — Lua 테이블의 최상위 이름 (옵션: `HealGuideData` 로 바꿔도 됨)

---

## 10. 참고 링크

- [WarcraftLogs API v2 문서](https://www.warcraftlogs.com/v2-api-docs/warcraft/)
- [WarcraftLogs OAuth 가이드](https://www.warcraftlogs.com/api/docs)
- [Blizzard WoW API 문서 (Wowpedia)](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [COMBAT_LOG_EVENT_UNFILTERED 이벤트](https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT_UNFILTERED)
