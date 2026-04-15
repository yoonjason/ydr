# HealGuide 작업 인계 (2026-04-15)

집 PC 로 이어받기 위한 상태 인계 문서. 순서대로 따라가면 이전 세션 컨텍스트를 복원할 수 있습니다.

## 현재 위치 (Git)

- 브랜치: `main`
- 최신 커밋: **`Phase 3 애드온: 블로커 패치 + 통합 탭창 + 펄스 애니메이션`** (`24d42ca`)
- 푸시 상태: `origin/main` 동기화됨
- uncommitted 변경: 이 HANDOFF + S-new-3 TTS 패치 (MainFrame.lua) — 다음 커밋에 포함

## 집 PC 최초 세팅 (3단계)

```sh
# 1. 리포지토리 가져오기
git clone https://github.com/yoonjason/ydr.git     # 또는 git pull
cd ydr

# 2. 메모리 심링크 1회 생성 (최초 1회만)
#    아래 경로는 이 Mac 의 경로. 집 PC 프로젝트 경로가 다르면
#    ~/.claude/projects/- 뒤의 디렉터리 이름도 슬래시를 대시로 변환한 새 경로가 됩니다.
#    예: /Users/foo/work/ydr → ~/.claude/projects/-Users-foo-work-ydr/memory
mkdir -p ~/.claude/projects/-Users-bradley-Documents-yegonseok2-ydr
ln -s "$(pwd)/.claude/memory" \
  ~/.claude/projects/-Users-bradley-Documents-yegonseok2-ydr/memory

# 3. Claude Code 시작
claude
```

첫 프롬프트에 "HANDOFF.md 읽고 이어가자" 로 시작하면 됩니다.

## 현재 상태 요약

### 완료된 것
1. **Mac 앱** (Phase 1~1.5) — WarcraftLogs URL → import 문자열 생성, 102 테스트 통과
2. **WoW 애드온 Phase 3** — import 기반 SavedVariablesPerCharacter + 자동 활성
   - 1차 code-reviewer 리뷰의 블로커 4건(B1 C_Spell API, B2 NewTimer, B3 프레임 풀, B4 for 패턴) 전부 패치
   - 1차 SUGGESTION/NITS 8건 전부 반영
   - 통합 탭창 3개(데이터/설정/미리보기) 재설계
   - 펄스 애니메이션 (OnUpdate 2단계)
   - 아이콘 기본/확대 크기 2슬라이더
   - TTS (`C_VoiceChat.SpeakText`, pcall 감쌈)
   - `/hg size`, `/hg pulse`, `/hg tts`, `/hg sound`, `/hg label` 슬래시
3. **luajit 문법 검증** — 9 파일 전부 통과 (luac5.1 없어서 luajit 사용)
4. **수동 code-review** — 이전 블로커 회귀 없음 확인

### 미완료 / 집에서 할 일

**우선순위 1: 인게임 실기 테스트 (가장 중요)**

`addon/TESTING.md` 의 16개 섹션 체크리스트를 따라 진행:

1. 심링크로 애드온 설치
   ```sh
   ln -s "$(pwd)/addon/HealGuide" \
     "$HOME/Applications/World of Warcraft/_retail_/Interface/AddOns/HealGuide"
   ```
2. 와우 실행 → 힐러 캐릭터 접속 → `/hg`
3. 로드 확인 → 에러 없으면 탭창 열림
4. Mac 앱으로 테스트 URL 에서 import 문자열 생성 후 `/hg import`
5. 설정 탭에서 크기/위치/사운드/TTS 조정
6. 미리보기 탭의 "알림 테스트" 버튼으로 즉시 시연
7. `/hg test <encID>` 로 시뮬레이션
8. 실제 M+ 던전 진입해서 자동 활성 검증

**테스트 URL**: `https://www.warcraftlogs.com/reports/XqwA2yHChmM87GjR?fight=3&type=casts&source=143&view=timeline` (수양 사제, 4보스 M+)

### 알려진 불확실 요소 (에이전트 가정)

인게임에서 에러가 나면 우선 이 3곳을 의심하세요:

1. **`C_VoiceChat.GetTtsVoices()` 반환 필드명**
   - 가정: `voiceID`, `name` 필드가 있음
   - 현재 `_RefreshVoiceLabel` / `_OpenVoiceMenu` 는 pcall 로 감싸서 에러 시 폴백 동작
   - 실제 필드명이 다르면 드롭다운이 빈 목록 표시. **크래시 없음.**
   - 수정 위치: `addon/HealGuide/UI/MainFrame.lua` `_RefreshVoiceLabel`, `_OpenVoiceMenu`

2. **`EasyMenu` deprecated (TWW 10.2.5+)**
   - 아직 동작하지만 공식 권장 API 는 `MenuUtil.CreateContextMenu`
   - 집 PC 에서 `/hg` → 설정 탭 → TTS 선택 버튼 누르면 결과 확인
   - 에러 시 `MainFrame.lua:_OpenVoiceMenu` 를 신 Menu API 로 교체

3. **`UIRadioButtonTemplate`**
   - 일부 클라이언트 버전에서 누락 가능
   - 현재 `pcall` 로 감싸서 `UICheckButtonTemplate` 로 폴백 (MainFrame.lua:501-505)
   - 알림 모드 라디오가 체크박스처럼 보이면 템플릿 폴백이 작동한 것

### 알려진 이슈 (비블로커)

- **`DungeonMappings.lua` 데드 코드** — encounterID→instanceMapID 테이블이 정의돼 있지만 아무 곳에서도 호출 안 함. 원래 zone 진입 토스트에 쓰려던 건데 `OnZoneChanged` 가 `Storage:GetDungeons()` 로만 판단. 삭제 or 연결 결정 필요.
- **레이드 단일 보스 import** — Mac 앱에서 dungeonName 이 보스 이름으로 들어감 (Mac 앱 S-2 한계, 설계상 제약)
- **Mac 앱 잔여 SUGGESTION** — S-1 ISO8601 formatOptions, N-1 Mock 튜플 라벨. 블로커 아님.

## 파일 구조 요약

```
addon/HealGuide/
├── HealGuide.toc              ← Interface 110200, SavedVariablesPerCharacter
├── Data/
│   └── DungeonMappings.lua    ← 데드코드 (DEAD-1)
├── Core/
│   ├── Init.lua               ← 이벤트 + 슬래시 명령어
│   ├── Storage.lua            ← HealGuideCharDB + 마이그레이션
│   ├── SpecMatcher.lua        ← 7힐러 스펙 감지
│   ├── ImportParser.lua       ← loadstring + setfenv({}) 샌드박스
│   └── EncounterEngine.lua    ← reactive/absolute/hybrid + pendingTimers
└── UI/
    ├── AlertFrame.lua         ← OnUpdate 펄스 애니메이션 + TTS
    ├── ImportDialog.lua       ← 붙여넣기 다이얼로그
    └── MainFrame.lua          ← 통합 탭창 3개 (~700줄)
```

## 핵심 메모리 파일 위치

- `.claude/memory/MEMORY.md` — 인덱스
- `.claude/memory/phase1_svs_pending.md` — Mac 앱 잔여 개선 사항
- `.claude/memory/phase3_addon_handoff.md` — Phase 3 상세 상태

## 다음 세션 시작 시 추천 프롬프트

```
HANDOFF.md 읽고 이어가자. 집 PC 라서 일단 인게임 로드 확인 먼저 해볼게.
```

또는:

```
HANDOFF.md 읽고 S-new-3 (TTS 필드명) 부터 인게임 검증해줘.
```

## 비상 연락처

- Repo: https://github.com/yoonjason/ydr
- 현재 커밋 전 롤백: `git reset --hard 24d42ca`
