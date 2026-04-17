# Midnight M+ HealGuide 확장 계획

> 작성일: 2026-04-17
> 대상: `addon/HealGuide` (Interface 120000, Midnight 12.0.x)
> 목적: ENCOUNTER_START 기반 현재 구조를 쐐기(Mythic+) 시나리오까지 점진적으로 확장하기 위한 리서치 및 설계.

---

## 1. 시즌 정보

| 항목 | 값 | 비고 |
|------|-----|-----|
| 확장팩 | World of Warcraft: Midnight | 2026-03-02 정식 출시 (얼리 2026-02-27) |
| 현재 시즌 | **Midnight Season 1** | Mythic 던전 2026-03-17 주, M+ 2026-03-24 주 개방 |
| 시즌 종료 예정 | 2026-06-23 | Blizzard 공식 발표 기준 |
| 주요 패치 | 12.0.0 (출시), **12.0.5** (2026-04-21 미주) | 현재 시점(04-17) 기준 라이브는 12.0.0 계열, 12.0.5 임박 |
| 애드온 Interface | 120000 (현재 `HealGuide.toc` 와 일치) | 12.0.5 진입 시 120005 변경 필요 여부 확인 |

**확인 필요**: 12.0.5 패치에서 시즌 구성/어픽스/던전 풀 변경이 없다고 공식 발표되었는지 — 현재 기사들은 하우징/보상 중심 업데이트로 묘사함. 릴리즈 노트 최종본 확인 후 TOC bump 여부 결정.

출처:
- https://www.wowhead.com/guide/midnight/season-1-overview-dungeons-raids-dates
- https://news.blizzard.com/en-us/article/24266321/midnight-season-1-mythic-now-available
- https://www.icy-veins.com/wow/midnight-mythic-season-1-guide
- https://warcraft.wiki.gg/wiki/Midnight_Season_1
- https://www.wowhead.com/news/midnight-patch-12-0-5-releases-april-21st-381173

---

## 2. 던전 로스터 (Season 1, 8개)

| # | 던전 (dungeonKey 제안) | 원 확장팩 | 출처 |
|---|---|---|---|
| 1 | Magisters' Terrace (`MagistersTerrace`) | Burning Crusade | warcraft.wiki.gg |
| 2 | Pit of Saron (`PitOfSaron`) | Wrath of the Lich King | warcraft.wiki.gg (WotLK 던전 최초 M+ 편입) |
| 3 | Skyreach (`Skyreach`) | Warlords of Draenor | warcraft.wiki.gg |
| 4 | Seat of the Triumvirate (`SeatOfTriumvirate`) | Legion | warcraft.wiki.gg |
| 5 | Algeth'ar Academy (`AlgetharAcademy`) | Dragonflight | warcraft.wiki.gg |
| 6 | Windrunner Spire (`WindrunnerSpire`) | Midnight (신규) | warcraft.wiki.gg |
| 7 | Maisara Caverns (`MaisaraCaverns`) | Midnight (신규) | warcraft.wiki.gg |
| 8 | Nexus-Point Xenas (`NexusPointXenas`) | Midnight (신규) | warcraft.wiki.gg |

> 시즌 내내 동일 8개 풀 유지 (로테이션 없음).

출처:
- https://warcraft.wiki.gg/wiki/Midnight_Season_1
- https://news.blizzard.com/en-us/article/24266321/midnight-season-1-mythic-now-available
- https://www.wowhead.com/guide/midnight/mythic-plus-season-1-overview

> **검증 노트**: 초기 한 커뮤니티 기사(koroboost, 2026-03)에서 "Murder Row / Den of Nalorakk"를 포함한 리스트가 유통되었으나, 공식 Blizzard 발표 및 warcraft.wiki.gg 의 공식 시즌 1 문서와 불일치. 본 문서는 공식 소스를 채택.

---

## 3. 어픽스 구조 (Midnight S1)

| 키스톤 레벨 | 어픽스 |
|---|---|
| +2 ~ +4 | **Lindormi's Guidance** (신규 시즌 어픽스, 뉴비 친화 — 루트 가이드 마킹, 사망 시 타이머 감산 무효) |
| +5 ~ +6 | + **Xal'atath's Bargain** 주간 변종 1개 |
| +7 ~ +9 | + **Tyrannical 또는 Fortified** 주간 순환 (TWW 방식 계승) |
| +10 ~ +11 | Tyrannical **와** Fortified 동시 적용 |
| +12+ | Bargain 제거 → **Xal'atath's Guile** (사망 페널티 극대화) |

### Xal'atath's Bargain 4종 (주간 순환)
1. **Ascendant** — 디스펠/인터럽트/넉백으로 처리해야 하는 적 등장
2. **Voidbound** — 보이드바운드 에미서리 스왑 + Dark Prayer 인터럽트 분담
3. **Pulsar** — 펄서 디버프를 서로에게 붙여 해제 (단순)
4. **Devour** — 5개 중 2개만 힐러 디스펠로 커버, 나머지는 개인 생존기

출처:
- https://www.wowhead.com/affix=165/lindormis-guidance
- https://www.wowhead.com/news/mythic-affix-changes-in-midnight-379221
- https://raider.io/news/740-midnight-mythic-plus-affixes
- https://www.icy-veins.com/wow/midnight-mythic-season-1-guide

---

## 4. 던전별 힐러 Critical Cast

> 각 던전 Top 2~3. spellID는 **wowhead 직접 링크**로 검증 가능하게 표기.
> 유형: `party-dmg`(광역), `tank-buster`, `dispel-urgent`, `interrupt-critical`
> **검증 필요 표시(⚠)**: Method.gg ability tracker 수집값 기준 — 12.0.5 패치 시 spellID 변동 가능성 있음.

> **검증 수행 요약 (2026-04-17)**: 대상 ⚠ 17건을 wowhead spell 상세 + Method.gg ability tracker(라이브 M+ 로그 기반)로 교차 검증.
> - 일치(⚠ 제거): 16건
> - 부분 불일치(이름 상이, spellID는 유효): 1건 — 4.3 Skyreach `Solar Orb` (1254329). Method.gg 는 "Solar Orb" 로, wowhead spell DB 는 동일 ID 를 "Solar Flare" 로 표기. Midnight 패치 과정에서 내부 이름 변경된 것으로 추정되며 ID 자체는 라이브 시전 확인. 주석으로 명기하되 ID 는 유지.
> - spellID 교체(before→after): 0건
> - 미확인 유지: 0건

### 4.1 Magisters' Terrace
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Arcanotron Custos (보스) | Ethereal Shackles | [1214038](https://www.wowhead.com/spell=1214038) | dispel-urgent | Magic 디스펠 즉시 — 검증완료 (2026-04-17) |
| Degentrius (보스) | Devouring Entropy | [1215897](https://www.wowhead.com/spell=1215897) | party-dmg | 광역 쿨 예약 (크고 예측 가능) — 검증완료 (2026-04-17) |
| Lightward Healer (트래시) | Power Word: Shield | [1254306](https://www.wowhead.com/spell=1254306) | interrupt-critical | 퍼플렉스 실드 인터럽트 분담 — 검증완료 (2026-04-17) |

### 4.2 Pit of Saron
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Dreadpulse Lich (트래시) | Dread Pulse | [1258798](https://www.wowhead.com/spell=1258798) | party-dmg | 광역 쿨 — 검증완료 (2026-04-17) |
| Rimebone Coldwraith (트래시) | Permeating Cold | [1258437](https://www.wowhead.com/spell=1258437) | party-dmg + dispel | 디스펠 + 광역 — 검증완료 (2026-04-17) |
| Scourgelord Tyrannus (보스) | Festering Pulse | [1262997](https://www.wowhead.com/spell=1262997) | party-dmg | 광역 쿨 (버프 동반) — 검증완료 (2026-04-17) |

### 4.3 Skyreach
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Araknath (보스) | Supernova | [154135](https://www.wowhead.com/spell=154135) | party-dmg | 광역 쿨, 빔 블로커 우선 힐 |
| High Sage Viryx (보스) | Solar Blast | [154396](https://www.wowhead.com/spell=154396) | tank-buster | 탱 외힐 + 디펜시브 유도 |
| Solar Elemental (트래시) | Solar Orb | [1254329](https://www.wowhead.com/spell=1254329) | party-dmg | 광역 쿨 — 검증완료 (2026-04-17). ID 는 Method.gg 라이브 트래커에서 "Solar Orb" 로 확인, 단 wowhead DB 는 동일 ID 를 "Solar Flare" 로 표시(내부명 변경 추정) |

### 4.4 Seat of the Triumvirate
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Saprish (보스) | Dread Screech | [248831](https://www.wowhead.com/spell=248831) | interrupt-critical | 인터럽트 분담 (CC 동반) |
| Zuraal the Ascended (보스) | Crashing Void | [1263297](https://www.wowhead.com/spell=1263297) | party-dmg | 광역 쿨 — 검증완료 (2026-04-17) |
| Viceroy Nezhar (보스) | Collapsing Void | [1263529](https://www.wowhead.com/spell=1263529) | party-dmg | 광역 + 포지셔닝 — 검증완료 (2026-04-17) |

### 4.5 Algeth'ar Academy
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Overgrown Ancient (보스) | Healing Touch | [396640](https://www.wowhead.com/spell=396640) | interrupt-critical | 보스 자힐 인터럽트 |
| Overgrown Ancient (보스) | Lasher Toxin | [참고](https://www.wowhead.com/spell=389813) | dispel-urgent | 탱/메인 타겟 Poison 디스펠 |
| Echo of Doragosa (보스) | Overwhelming Power | [389011](https://www.wowhead.com/spell=389011) | party-dmg | Arcane Fissure 광역 쿨 |

### 4.6 Windrunner Spire
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Bloated Lasher (트래시) | Spore Dispersal | [1216963](https://www.wowhead.com/spell=1216963) | tank-buster | 탱 외힐 + 디펠 여부 확인 — 검증완료 (2026-04-17) |
| Devoted Woebringer (트래시) | Pulsing Shriek | [473668](https://www.wowhead.com/spell=473668) | interrupt-critical | 인터럽트 우선 |
| Phantasmal Mystic (트래시) | Chain Lightning | [1216592](https://www.wowhead.com/spell=1216592) | interrupt-critical | 2인 이상 피해, 커트 — 검증완료 (2026-04-17) |
| Emberdawn (보스) | Burning Gale | [465904](https://www.wowhead.com/spell=465904) | party-dmg | 광역 쿨 |
| Restless Heart (보스) | Bolt Gale | [참고 위키](https://warcraft.wiki.gg/wiki/Windrunner_Spire) | tank-buster | 지정 대상 외힐 |

### 4.7 Maisara Caverns (S1 최다 인터럽트 던전)
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Dread Souleater (트래시) | Necrotic Wave | [1257088](https://www.wowhead.com/spell=1257088) | interrupt-critical | 힐 흡수, 절대 인터럽트 — 검증완료 (2026-04-17) |
| Ritual Hexxer (트래시) | Hex | [1256008](https://www.wowhead.com/spell=1256008) | interrupt-critical | 인터럽트 실패 시 Magic 디스펠 — 검증완료 (2026-04-17) |
| Hulking Juggernaut (트래시) | Deafening Roar | [1256047](https://www.wowhead.com/spell=1256047) | party-dmg | 회피 불가 광역 — 검증완료 (2026-04-17) |
| Vordaza (보스) | Necrotic Convergence | [1250708](https://www.wowhead.com/spell=1250708) | party-dmg | 최대 쿨 예약 — 검증완료 (2026-04-17) |

### 4.8 Nexus-Point Xenas
| 보스/트래시 | 스킬 | spellID | 유형 | 힐러 대응 |
|---|---|---|---|---|
| Lightwrought (트래시) | Burning Radiance | [1277557](https://www.wowhead.com/spell=1277557) | party-dmg + dispel | Magic 디스펠 + 광역 — 검증완료 (2026-04-17) |
| Null Sentinel (트래시) | Dreadbellow | [1252406](https://www.wowhead.com/spell=1252406) | party-dmg | 광역 쿨 — 검증완료 (2026-04-17) |
| Lothraxion (보스) | Divine Guile | [1257595](https://www.wowhead.com/spell=1257595) | interrupt-critical + party-dmg | 인터럽트 실패 시 광역 쿨 — 검증완료 (2026-04-17) |

> 2026-04-17 재검증 완료: ⚠ 마커 17건 전부 Method.gg ability tracker 및 wowhead spell 상세 페이지로 교차 확인됨. 예외 1건(Skyreach `Solar Orb` 1254329)은 ID 는 유효하나 wowhead 측 내부명이 "Solar Flare" 로 상이 — 라이브 패치에서 문제 재확인 시 데이터 생성 단계에서 보정.

---

## 5. 설계 제안 A~E

### A) ConditionEvaluator DSL 확장

현재 `ConditionEvaluator.lua` 는 화이트리스트 기반 리프 필드(`ALLOWED_FIELDS`) + 연산자(`ALLOWED_OPS`) 구조. M+ 컨텍스트 필드를 세 가지 추가:

- `keystoneLevel` (integer, `C_ChallengeMode.GetActiveKeystoneInfo()` 의 level)
- `affixActive` (eq 전용, `node.affixID` 로 판별 — spellOnCooldown 과 동일 패턴)
- `dungeonKey` (eq 전용, `node.value` = 문자열; 기존 `value: number` 계약 깨지므로 `stringValue` 필드 도입)

Collector 는 `CHALLENGE_MODE_START`/`PLAYER_ENTERING_WORLD` 이벤트에서 1회 캐싱 → 인카운터 중 재조회 불필요. `encounterTimeElapsed` 처럼 동적 필드 아님.

**최소 침습 포인트**: (1) `ALLOWED_FIELDS` 에 3개 추가 (2) `Evaluator:Evaluate` 에 `affixActive`/`dungeonKey` 분기를 `spellOnCooldown` 블록과 동형으로 추가 (3) `BuildContext` 에 정적 필드 2개만 프리컴퓨트 (4) `RunSelfTest` 에 회귀 체크 3건 추가. 기존 조건 트리/데이터 파일은 무변경.

**우선순위**: Must `keystoneLevel`, Should `dungeonKey`, Could `affixActive` (라이브 어픽스 ID 매핑 확정 후).

---

### B) 트래시 구간 알림 — 3가지 접근 트레이드오프

현재는 `ENCOUNTER_START`/`ENCOUNTER_END` 로만 타임라인 구동. 쐐기 트래시는 이 이벤트 밖이므로 보완 필요.

| 접근 | 장점 | 단점/리스크 |
|---|---|---|
| **B1. CHALLENGE_MODE_START + 풀 타이머** | 순수 블리자드 이벤트, taint 없음. 던전 시작 시각을 기준으로 사전 편성한 풀별 offset 재생. | 사전 편성 데이터를 수집/유지해야 함. 스킵/역순 풀링 시 무의미. |
| **B2. MDT(Mythic Dungeon Tools) 훅** | 커뮤니티 루트 재사용. 사용자가 MDT 로 짠 루트 그대로 이용. | MDT 설치 의존. API 비공식(`MDT:GetCurrentPull()` 등 소스 분석 필요). MDT 버전 변화에 깨짐. 메인 UI 에 이벤트 구독 구조 없음 → 폴링 필요. |
| **B3. UNIT_SPELLCAST_SUCCEEDED 화이트리스트** | 실시간 반응. 타이밍 정확. 루트 무관. | CLEU 와 달리 캐스트 실패/차단 구분 필요. 화이트리스트 관리 코스트. 대규모 구간에서 nameplate 관련 perf 영향. |

**taint 리스크 비교**: B1은 자체 프레임 타이머 → 제로. B2는 MDT 가 protected API 호출 시 우리 콜스택에 상주하면 오염 가능, 읽기 전용 접근 유지 필수. B3은 이벤트 핸들러라 taint 없음.

**권장 MVP**: **B3 + B1 하이브리드** — 단기로는 B3 로 "당장 위험한 캐스트 보이면 알림" 을 트래시에서도 동작하게 하고, 이후 B1 의 사전 편성 타임라인을 얹는다. B2는 옵트인 확장으로 보류.

---

### C) 인터럽트 분담 마커 (TimelineFrame)

힐러 스펙 중 인터럽트 가능: **MistweaverMonk** (파쇄 돌풍 115750), **PresEvoker** (Quell 351338), **HolyPaladin** (Rebuke 96231), **DiscPriest/HolyPriest** (Silence 15487 Discipline 한정), **RestoShaman** (Wind Shear 57994), **RestoDruid** (Skull Bash 106839).

현재 `TimelineFrame.lua` 는 힐 콜 알림 중심. interrupt-critical 태그가 있는 엔트리에 대해 **다른 색(오렌지) border** 를 부여하고, 플레이어가 해당 스펙이면서 쿨이 돌아올 경우 "담당" 아이콘을 추가.

**가치 vs 복잡도**: 가치 = 힐러가 인터럽트 주도를 맡아야 하는 컴프(예: Mistweaver + DK + 원딜 2) 에서 실전 생존률 향상. 복잡도 = entry 에 `interruptCapable` 메타 1개 추가 + 스펙→인터럽트 spellID 매핑 테이블 1개 + TimelineFrame 렌더 분기 1개. 낮음.

**우선순위**: Should (MVP 이후 애드온 UX 2차 묶음).

---

### D) 키스톤 레벨별 threshold 분기

+2 ~ +11 과 +12+ 는 Guile 발동으로 위험도 차이 큼. 현재 엔트리 스키마에 `minKeystone` 옵션 필드 추가:

```lua
{ spellID = 1256047, delay = 3.2, minKeystone = 10 }  -- +10 이상에서만 알림
```

ConditionEvaluator 에 `keystoneLevel` 이 들어가면 조건 트리 안에서도 동일 제어 가능하지만, 엔트리별 threshold 는 **데이터 작성자의 간편 문법** 이라 별도 키로 유지. 앱(`app/`) 의 Lua 생성기에서 설정하고 애드온 런타임에서 필터.

**UI 위치**: MainFrame 설정 탭에 "알림 레벨 하한" 슬라이더 (2~12). 기본값 2. 사용자가 +15 부터만 보고 싶으면 올림. SavedVariables: `HealGuideCharDB.settings.keystoneMinLevel`.

**우선순위**: Must (데이터 필드 추가는 1시간 미만, UI 슬라이더는 Should).

---

### E) MDT 연동 실현 가능성

- MDT 는 `MethodDungeonTools` 전역을 `MDT` 별칭으로 노출. 소스 분석 결과 `MDT:GetCurrentPull()` 라는 함수가 `MethodDungeonTools.lua` 내부에 존재(공식 API 문서화 안 됨).
- 공개 이벤트 디스패처 없음 → 폴링 또는 MDT 의 내부 콜백을 monkey-patch 하는 방식 필요. 두 방식 모두 MDT 업데이트 시 깨질 수 있음.
- MDT 미설치 시 NoOp 이어야 함. `if not MethodDungeonTools then return end` 가드 필수.
- **의존성 취급**: `## OptionalDeps: MythicDungeonTools` 를 TOC 에 추가하되 하드 디펜던시는 피한다.

**권장**: Phase 2 이후 애드온 이름 변경(예: `HealGuide_MDT` 서브모듈) 으로 선택형 확장. 코어는 MDT 무관하게 동작.

**우선순위**: Could (MVP 범위 밖).

---

## 6. MVP 슬라이스 — 지금 당장 할 수 있는 가장 작은 한 덩어리

> **슬라이스명**: "S1-M1 Keystone-aware Alert Gate"
>
> **목표**: 시즌 1 던전 8개에 대한 ENCOUNTER 데이터를 그대로 유지하면서, **쐐기 레벨 하한 1개** 만 도입해 저렙 키에서 불필요한 알림을 끈다.
>
> **범위** (파일 3개, 코드 약 60줄):
> 1. `Core/ConditionEvaluator.lua` — `ALLOWED_FIELDS.keystoneLevel = true` 추가, `BuildContext` 에 `C_ChallengeMode.GetActiveKeystoneInfo()` 결과 캐싱 추가. `RunSelfTest` 에 "keystoneLevel gte 10" 케이스 3건.
> 2. `Core/EncounterEngine.lua` (또는 Init) — `CHALLENGE_MODE_START` 에서 현재 레벨 저장, `CHALLENGE_MODE_COMPLETED`/`PLAYER_ENTERING_WORLD` 에서 리셋.
> 3. `Core/Storage.lua` — `HealGuideCharDB.settings.keystoneMinLevel` 기본값 2, getter/setter.
>
> **DoD**:
> - Key +2 ~ +9 범위에서 `conditionFallback = false` 설정 + 엔트리에 `{op="gte", field="keystoneLevel", value=10}` 조건을 붙였을 때 알림이 안 뜬다.
> - +10 이상 키에서 기존 모든 알림이 그대로 발화.
> - 비 M+ 던전(비 CM 인스턴스)에서는 `keystoneLevel = 0` 반환 → 기존 보스 알림 영향 없음.
> - 자체 테스트 통과 + 실기 1회(+7 키 통과).
>
> **MVP 에서 명시적으로 제외**:
> - 트래시 알림(B), 인터럽트 마커(C), 어픽스 필드(affixActive), MDT 연동(E), 어픽스별 엔트리 필터.
> - 던전별 신규 데이터(4장 표)는 본 슬라이스에서 **스키마만 준비**하고 실제 수집은 다음 슬라이스.

슬라이스 완료 후 다음 후보: (1) `dungeonKey` 필드 추가 + 시즌 1 던전 8종 매핑 테이블, (2) 4장의 Critical Cast 표 spellID 를 라이브 로그로 재검증하여 `HealGuide_Generated.lua` 에 첫 M+ 엔트리 투입.
