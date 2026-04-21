import Foundation
import os

@MainActor
final class RankerCollectionViewModel: ObservableObject {

    // MARK: - View State

    enum ViewState {
        case idle
        case collecting(RankerCollectionProgress)
        case preview(RankerPreviewResult, HGPTRankerData)
        case failure(String)
    }

    // MARK: - 입력 상태

    @Published var selectedDungeon:    DungeonInfo?    = DungeonInfo.currentSeason.first
    @Published var selectedDifficulty: RankerDifficulty = .mythicPlus
    @Published var selectedSpec:       HealerSpec      = .discPriest
    @Published var topNCount:          TopNCount        = .ten
    @Published var selectedPreset:     TalentPreset?
    @Published var talentString:       String           = ""
    @Published var isAdvancedMode:     Bool             = false
    @Published var useGlobalFallback:  Bool             = false
    @Published var jaccardThreshold:   Double           = 0.8

    // WarcraftLogs 자격증명 (로그 분석 탭과 동일 Keychain 키 공유)
    @Published var clientID:     String = ""
    @Published var clientSecret: String = ""

    // WoW AddOns 경로 (리포트 탭과 동일 UserDefaults 키 공유)
    @Published var wowAddonsPath: String = "" {
        didSet { persistWowAddonsPath() }
    }

    // 출력 상태
    @Published var state:           ViewState = .idle
    @Published var lastSaveResult:  String?
    @Published var talentParseError: String?
    // 현재 preview 가 파일에 저장되었는지. 메시지 문자열 매칭 대신 명시적 플래그로 관리.
    @Published var isSaved:         Bool = false

    // MARK: - Dependencies

    private let apiClient:        any WarcraftLogsAPIClient
    private let rankingService:   any CharacterRankingsService
    private let filterService:    any TalentFilterService
    private let merger:           any RankerDataMerger
    private let serializer:       RankerLuaSerializer
    private let cacheService:     RankerCacheService
    private let keychain:         any KeychainStoring
    private let blizzardKeychain: any KeychainStoring
    private let nameResolver:     any RankerNameResolver
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "RankerVM")

    private var suppressPersist: Bool = false
    // 이름 해상 백그라운드 Task 참조 — 재수집 시 이전 Task 취소로 불필요한 API 호출 회피.
    private var enrichTask: Task<Void, Never>?
    // 수집 전체 Task — 사용자가 '중지' 버튼을 누르면 취소
    private var collectTask: Task<Void, Never>?

    init(
        apiClient:        any WarcraftLogsAPIClient      = WarcraftLogsAPIClientImpl(),
        rankingService:   any CharacterRankingsService   = CharacterRankingsServiceImpl(),
        filterService:    any TalentFilterService        = TalentFilterServiceImpl(),
        merger:           any RankerDataMerger           = RankerDataMergerImpl(),
        keychain:         any KeychainStoring            = FileCredentialStore(),
        blizzardKeychain: any KeychainStoring            = FileCredentialStore(fileName: "blizzard_credentials.json"),
        nameResolver:     any RankerNameResolver         = RankerNameResolverImpl(),
        cacheService:     RankerCacheService             = RankerCacheService()
    ) {
        self.apiClient        = apiClient
        self.rankingService   = rankingService
        self.filterService    = filterService
        self.merger           = merger
        self.keychain         = keychain
        self.blizzardKeychain = blizzardKeychain
        self.nameResolver     = nameResolver
        self.cacheService     = cacheService
        self.serializer       = RankerLuaSerializer()
    }

    // MARK: - 초기화

    func onAppear() {
        suppressPersist = true
        defer { suppressPersist = false }
        if clientID.isEmpty, let id = keychain.loadClientID() {
            clientID = id
        }
        if clientSecret.isEmpty, let secret = keychain.load() {
            clientSecret = secret
        }
        if wowAddonsPath.isEmpty {
            wowAddonsPath = UserDefaults.standard.string(forKey: "wowAddonsPath") ?? ""
        }
    }

    private func persistWowAddonsPath() {
        guard !suppressPersist, !wowAddonsPath.isEmpty else { return }
        UserDefaults.standard.set(wowAddonsPath, forKey: "wowAddonsPath")
    }

    // MARK: - 탤런트 스트링 검증 (실시간)

    func validateTalentString() {
        guard !talentString.trimmingCharacters(in: .whitespaces).isEmpty else {
            talentParseError = nil
            return
        }
        if filterService.parseTalentString(talentString) != nil {
            talentParseError = nil
        } else {
            talentParseError = "스트링 파싱 실패 — 게임 내 [탤런트 내보내기] 스트링을 확인해주세요."
        }
    }

    // MARK: - 필터 완화 (0.8 → 0.6)

    func relaxFilter() {
        jaccardThreshold = 0.6
        reapplyFilter()
    }

    // MARK: - 수집 실행

    // View 진입점. 이전 Task 취소 후 새 수집 시작.
    func startCollect() {
        collectTask?.cancel()
        lastSaveResult = nil
        isSaved = false
        // Task tail 에서 collectTask = nil 을 쓰지 않는 이유:
        // cancel() + startCollect 연타 시 이전 Task 의 tail 이 뒤늦게 실행되면
        // 새로 생성된 collectTask 참조를 덮어써 '중지' 버튼이 무력화되는 버그 방지.
        // 완료된 Task 참조는 다음 startCollect 또는 cancelCollect/reset 에서 정리됨.
        collectTask = Task { [weak self] in
            await self?.collect()
        }
    }

    // 현재 preview 결과가 파일에 아직 저장되지 않았는지 여부.
    var hasUnsavedPreview: Bool {
        guard case .preview = state else { return false }
        return !isSaved
    }

    // 진행 중인 수집 취소. enrich 도 함께 취소. state → idle.
    func cancelCollect() {
        collectTask?.cancel()
        collectTask = nil
        enrichTask?.cancel()
        enrichTask = nil
        state = .idle
    }

    private func collect() async {
        guard let dungeon = selectedDungeon else { return }
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            state = .failure("WarcraftLogs Client ID / Secret 을 입력해주세요.")
            return
        }

        // 이전 수집의 이름 해상 Task 가 돌고 있으면 취소 — 중복 Blizzard API 호출 방지
        enrichTask?.cancel()
        enrichTask = nil

        state = .collecting(RankerCollectionProgress(total: topNCount.rawValue, completed: 0, currentName: "인증 중..."))

        // 1. 액세스 토큰
        let token: String
        do {
            token = try await apiClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
        } catch {
            if Task.isCancelled { state = .idle; return }
            state = .failure("액세스 토큰 발급 실패: \(errorMessage(error))")
            return
        }
        if Task.isCancelled { state = .idle; return }

        // 2. characterRankings 조회
        updateProgress(total: topNCount.rawValue, completed: 0, name: "랭킹 조회 중...")

        let region = useGlobalFallback ? "" : "KR"
        let rawParses: [RankerParse]
        do {
            rawParses = try await rankingService.fetchCharacterRankings(
                encounterId:  dungeon.id,
                className:    selectedSpec.warcraftLogsClassName,
                specName:     selectedSpec.warcraftLogsSpecName,
                difficulty:   selectedDifficulty.warcraftLogsID,
                serverRegion: region,
                limit:        topNCount.rawValue,
                token:        token
            )
        } catch {
            if Task.isCancelled { state = .idle; return }
            state = .failure("characterRankings 조회 실패: \(errorMessage(error))")
            return
        }
        if Task.isCancelled { state = .idle; return }

        if rawParses.isEmpty {
            state = .failure("KR 서버에서 해당 조건의 랭킹 데이터가 없습니다. '전세계 확장' 옵션을 활성화해보세요.")
            return
        }

        // 3. 탤런트 필터
        let filterConfig = TalentFilterConfig(
            preset:            selectedPreset,
            talentString:      isAdvancedMode ? talentString : nil,
            jaccardThreshold:  jaccardThreshold
        )
        let filteredParses = filterService.filter(rawParses, using: filterConfig)

        if filteredParses.isEmpty {
            state = .failure("탤런트 필터 통과 파스가 0건입니다. '필터 완화' 또는 필터 조건을 변경해보세요.")
            return
        }

        // 4. 각 파스의 보스→힐 쌍 수집 + dungeonPulls.name 누적
        // per-pull encounterID 는 worldData.encounter(id:).name 에서 조회 불가 (nil 반환).
        // 대신 이 단계에서 fetchEncounters 응답의 BossWindow.name 을 직접 수집.
        let totalFiltered = filteredParses.count
        var parseResults: [(parse: RankerParse, bossPairs: [BossHealPair])] = []
        var collectedEncounterNames: [Int: String] = [:]

        for (index, parse) in filteredParses.enumerated() {
            if Task.isCancelled { state = .idle; return }
            updateProgress(total: totalFiltered, completed: index, name: "\(parse.characterName) 처리 중...")

            do {
                let result = try await fetchBossPairs(
                    parse: parse, spec: selectedSpec, token: token
                )
                parseResults.append((parse: parse, bossPairs: result.pairs))
                // 같은 encID 에 대해 후속 파스가 더 최신 이름을 주면 덮어씀
                collectedEncounterNames.merge(result.encounterNames) { _, new in new }
            } catch {
                logger.warning("파스 \(parse.reportCode)/\(parse.fightID) 스킵: \(error)")
                // 개별 파스 실패는 스킵 (전체 중단하지 않음)
            }
        }

        if parseResults.isEmpty {
            state = .failure("수집된 파스에서 유효한 보스→힐 데이터를 찾지 못했습니다.")
            return
        }

        // 5. 병합
        updateProgress(total: totalFiltered, completed: totalFiltered, name: "데이터 병합 중...")

        let nowKST = isoStringKST()
        let meta = HGPTRankerDataMeta(
            version:              1,
            collectedAt:          nowKST,
            region:               useGlobalFallback ? "World" : "KR",
            dungeonID:            dungeon.id,
            dungeonName:          dungeon.name,
            difficulty:           selectedDifficulty.rawValue,
            spec:                 selectedSpec.rawValue,
            rankersRequested:     topNCount.rawValue,
            rankersUsed:          parseResults.count,
            talentFilterPreset:   selectedPreset?.name ?? "",
            talentFilterString:   isAdvancedMode && !talentString.isEmpty,
            talentFilterSimilarity: isAdvancedMode ? jaccardThreshold : 0.0
        )

        // 5a. per-pull 보스명 영→한국어 번역 (Blizzard journal-instance 기반).
        // Blizzard 자격증명 없으면 영문 유지.
        if Task.isCancelled { state = .idle; return }
        let blizzardID     = loadBlizzardClientID()
        let blizzardSecret = loadBlizzardClientSecret()
        let dungeonKoreanName = extractKoreanName(dungeon.name)
        // Phase 3 용으로 번역 전 영문명 복사본 보존
        let originalEnglishNames = collectedEncounterNames
        var abilityDescriptions: [Int: [Int: String]] = [:]

        if !blizzardID.isEmpty && !blizzardSecret.isEmpty && !collectedEncounterNames.isEmpty {
            let translated = await nameResolver.translateEncountersToKorean(
                dungeonKoreanName:    dungeonKoreanName,
                englishNames:         collectedEncounterNames,
                blizzardClientID:     blizzardID,
                blizzardClientSecret: blizzardSecret
            )
            for (id, kr) in translated {
                collectedEncounterNames[id] = kr
            }

            // 5b. Phase 3 — 보스 스킬 기믹 설명 조회 (번역 성공한 경우만 유의미)
            if Task.isCancelled { state = .idle; return }
            abilityDescriptions = await nameResolver.fetchBossAbilityDescriptions(
                dungeonKoreanName:     dungeonKoreanName,
                englishEncounterNames: originalEnglishNames,
                blizzardClientID:      blizzardID,
                blizzardClientSecret:  blizzardSecret
            )
            logger.debug("collect(): translated=\(translated.count), abilityDescriptions=\(abilityDescriptions.count)")
        }

        var merged  = merger.merge(parses: parseResults, meta: meta, encounterNames: collectedEncounterNames)
        merged.abilityDescriptions = abilityDescriptions
        let preview = merger.buildPreview(
            parsesCollected: rawParses.count,
            parsesFiltered:  parseResults.count,
            data:            merged
        )

        state = .preview(preview, merged)

        // 이름 해상 — 백그라운드로 preview 업데이트. 자격증명 없거나 실패 시 숫자 유지.
        // originalEnglishNames 는 tactical 가이드 매칭 (WCL 영문 보스명 ↔ 가이드 엔트리) 에 필요.
        enrichTask = Task { [weak self] in
            await self?.enrichPreviewNames(
                currentPreview: preview,
                mergedData: merged,
                englishEncounterNames: originalEnglishNames
            )
        }
    }

    // MARK: - 이름 해상 (Blizzard API)

    private func enrichPreviewNames(
        currentPreview: RankerPreviewResult,
        mergedData: HGPTRankerData,
        englishEncounterNames: [Int: String] = [:]
    ) async {
        // encounter 이름은 WCL (자격증명 필수), spell 이름은 Blizzard (선택).
        // 한쪽만 있어도 부분 결과 반환.
        let wclID     = clientID
        let wclSecret = clientSecret
        let blizzardID     = loadBlizzardClientID()
        let blizzardSecret = loadBlizzardClientSecret()

        // encounter · spell 양쪽 다 자격증명 없으면 조회 의미 없음
        let hasWCL      = !wclID.isEmpty && !wclSecret.isEmpty
        let hasBlizzard = !blizzardID.isEmpty && !blizzardSecret.isEmpty
        guard hasWCL || hasBlizzard else { return }

        let encounterIDs = Set(currentPreview.bossEntries.map(\.encounterID))
        // Phase 2: 보스 스킬 + 힐러 스킬 모두 해상 → UI 가 힐러 스킬명도 한국어로 표시
        var spellIDs = Set(currentPreview.bossEntries.map(\.bossSpellID))
        for (_, bossMap) in mergedData.encounterData {
            for (_, entries) in bossMap {
                for entry in entries {
                    spellIDs.insert(entry.spellID)
                }
            }
        }

        let resolved = await nameResolver.resolveNames(
            encounterIDs: encounterIDs,
            spellIDs:     spellIDs,
            wclClientID:     wclID,
            wclClientSecret: wclSecret,
            blizzardClientID:     blizzardID,
            blizzardClientSecret: blizzardSecret
        )

        // enrich 도중 사용자가 다른 상태로 전환했으면 덮어쓰지 않음
        guard case .preview(let current, let data) = state, data.meta.collectedAt == mergedData.meta.collectedAt else {
            return
        }

        // 수집 단계에서 이미 채워진 encounterName 은 보존. resolver 는 WCL dungeon-level
        // encID 정도에만 name 을 줄 수 있고 per-pull 에는 nil 반환이므로 무조건 덮어쓰면
        // collect() 가 확보한 per-pull 이름이 날아감.
        let enrichedEntries = current.bossEntries.map { entry -> RankerPreviewResult.BossEntry in
            var copy = entry
            if let resolvedName = resolved.encounterNames[entry.encounterID], !resolvedName.isEmpty {
                copy.encounterName = resolvedName
            }
            if let resolvedSpell = resolved.spellNames[entry.bossSpellID], !resolvedSpell.isEmpty {
                copy.bossSpellName = resolvedSpell
            }
            return copy
        }

        let enrichedPreview = RankerPreviewResult(
            parsesCollected:       current.parsesCollected,
            parsesFiltered:        current.parsesFiltered,
            bossEntries:           enrichedEntries,
            highVarianceWarnings:  current.highVarianceWarnings
        )
        // enrichedData.encounterNames 에도 수집 단계 값 보존: resolver 결과로 덮어쓰지 않고 merge
        var enrichedData = data
        for (id, name) in resolved.encounterNames where !name.isEmpty {
            enrichedData.encounterNames[id] = name
        }
        // Phase 2: 힐러/보스 spellID 한국어 이름을 전체 맵에 주입 (UI 확장 렌더용)
        for (id, name) in resolved.spellNames where !name.isEmpty {
            enrichedData.spellNames[id] = name
        }
        // Phase 3b: 사용자 큐레이션 전술 가이드 매칭.
        // 매 (wclEncID, bossSpellID) 쌍에 대해, WCL 영문 보스명 + 한국어 스킬명 기준 lookup.
        if !englishEncounterNames.isEmpty {
            let dungeonID = enrichedData.meta.dungeonID
            var matched: [Int: [Int: [TacticalLine]]] = [:]
            print("[HG-TG-DEBUG] tacticalLines 매칭 시작 — dungeonID=\(dungeonID), 영문 보스명: \(englishEncounterNames.values)")
            for (encID, bossMap) in enrichedData.encounterData {
                guard let englishBossName = englishEncounterNames[encID] else {
                    print("[HG-TG-DEBUG]   encID=\(encID) englishBossName 없음 — 스킵")
                    continue
                }
                let bossGuide = TacticalGuideCatalog.bossGuide(forDungeonID: dungeonID, englishBossName: englishBossName)
                if bossGuide == nil {
                    print("[HG-TG-DEBUG]   '\(englishBossName)' catalog 매칭 실패")
                    continue
                }
                print("[HG-TG-DEBUG]   '\(englishBossName)' → '\(bossGuide!.koreanBossName)' 매칭 성공, \(bossGuide!.lines.count) 라인")
                for bossSpellID in bossMap.keys {
                    guard let spellKoreanName = enrichedData.spellNames[bossSpellID], !spellKoreanName.isEmpty else {
                        print("[HG-TG-DEBUG]     bossSpellID=\(bossSpellID) 스킬 한국어명 없음")
                        continue
                    }
                    let lines = TacticalGuideCatalog.matchingLines(
                        dungeonID: dungeonID,
                        englishBossName: englishBossName,
                        spellKoreanName: spellKoreanName
                    )
                    if !lines.isEmpty {
                        matched[encID, default: [:]][bossSpellID] = lines
                        print("[HG-TG-DEBUG]     bossSpellID=\(bossSpellID) '\(spellKoreanName)' → \(lines.count) 라인 매칭")
                    }
                }
            }
            enrichedData.tacticalLines = matched
            print("[HG-TG-DEBUG] tacticalLines 최종: \(matched.count)개 encounter")
            logger.debug("tacticalLines 매칭: \(matched.count)개 encounter")
        }
        state = .preview(enrichedPreview, enrichedData)
    }

    private func loadBlizzardClientID() -> String {
        blizzardKeychain.loadClientID() ?? ""
    }

    private func loadBlizzardClientSecret() -> String {
        blizzardKeychain.load() ?? ""
    }

    // DungeonInfo.name 이 '윈드러너 첨탑 (Windrunner Spire)' 형식이라 한국어 부분만 추출.
    // 괄호 + 공백 제거. 괄호 없으면 원본 반환.
    private func extractKoreanName(_ raw: String) -> String {
        if let idx = raw.firstIndex(of: "(") {
            return String(raw[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 병합 결과 저장

    func saveLua() {
        guard case .preview(_, let data) = state else { return }
        guard !wowAddonsPath.isEmpty else {
            lastSaveResult = "WoW AddOns 경로가 설정되어 있지 않습니다."
            return
        }

        let entries   = cacheService.merge(data)
        let filePath  = serializer.filePath(wowAddonsPath: wowAddonsPath)
        let directory = (filePath as NSString).deletingLastPathComponent
        let content   = serializer.serialize(entries)

        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            lastSaveResult = "저장 완료 (\(entries.count)개 항목): \(filePath)"
            isSaved = true
            logger.info("HGPT_RankerData.lua 저장: \(filePath) (\(entries.count) entries)")
        } catch {
            lastSaveResult = "저장 실패: \(error.localizedDescription)"
            isSaved = false
            logger.error("HGPT_RankerData.lua 저장 실패: \(error)")
        }
    }

    // MARK: - 초기화

    func reset() {
        collectTask?.cancel()
        collectTask = nil
        enrichTask?.cancel()
        enrichTask = nil
        state           = .idle
        lastSaveResult  = nil
        isSaved         = false
        jaccardThreshold = 0.8
    }

    // MARK: - Private Helpers

    private func reapplyFilter() {
        guard case .preview(_, let data) = state else { return }
        let preview = merger.buildPreview(
            parsesCollected: data.meta.rankersRequested,
            parsesFiltered:  data.meta.rankersUsed,
            data:            data
        )
        state = .preview(preview, data)
    }

    private func fetchBossPairs(
        parse: RankerParse,
        spec: HealerSpec,
        token: String
    ) async throws -> (pairs: [BossHealPair], encounterNames: [Int: String]) {
        // 보스 윈도우 + 힐러 sourceID 병렬 조회
        async let encounterFetch = apiClient.fetchEncounters(
            reportCode: parse.reportCode, fightID: parse.fightID, token: token
        )
        async let playerFetch = apiClient.fetchPlayerDetails(
            reportCode: parse.reportCode, fightID: parse.fightID, token: token
        )
        let (encounter, players) = try await (encounterFetch, playerFetch)

        // 보스 윈도우에서 per-pull 이름 수집 (worldData.encounter API 에서 조회 불가한 ID 들).
        var encounterNames: [Int: String] = [:]
        for window in encounter.windows {
            if !window.name.isEmpty {
                encounterNames[window.encounterID] = window.name
            }
        }

        // 대상 힐러 sourceID 탐색 (스펙 매칭)
        let matchingHealer = players.first { candidate in
            candidate.className  == spec.warcraftLogsClassName &&
            candidate.specName   == spec.warcraftLogsSpecName
        } ?? players.first { $0.healerSpec != nil }

        guard let healerCandidate = matchingHealer else {
            return (pairs: [], encounterNames: encounterNames)
        }

        // 각 보스 윈도우에서 쌍 추출
        var allPairs: [BossHealPair] = []

        try await withThrowingTaskGroup(of: [BossHealPair].self) { group in
            for window in encounter.windows {
                group.addTask {
                    async let healerCastsFetch = self.apiClient.fetchCasts(
                        reportCode:     parse.reportCode,
                        fightID:        parse.fightID,
                        sourceID:       healerCandidate.id,
                        hostilityType:  .friendly,
                        startTime:      window.startTime,
                        endTime:        window.endTime,
                        token:          token
                    )
                    async let bossCastsFetch = self.apiClient.fetchCasts(
                        reportCode:     parse.reportCode,
                        fightID:        parse.fightID,
                        sourceID:       nil,
                        hostilityType:  .hostile,
                        startTime:      window.startTime,
                        endTime:        window.endTime,
                        token:          token
                    )
                    let (healerCasts, bossCasts) = try await (healerCastsFetch, bossCastsFetch)
                    return Self.buildPairs(
                        encounterID:  window.encounterID,
                        bossCasts:    bossCasts,
                        healerCasts:  healerCasts,
                        windowStart:  window.startTime
                    )
                }
            }
            for try await pairs in group {
                allPairs.append(contentsOf: pairs)
            }
        }

        return (pairs: allPairs, encounterNames: encounterNames)
    }

    nonisolated static func buildPairs(
        encounterID:  Int,
        bossCasts:    [CastEvent],
        healerCasts:  [CastEvent],
        windowStart:  Int64
    ) -> [BossHealPair] {
        guard !bossCasts.isEmpty, !healerCasts.isEmpty else { return [] }

        // API 응답 순서가 타임스탬프 오름차순을 보장하지 않으므로 1회 정렬 후 재사용
        let sortedHealerCasts = healerCasts.sorted { $0.timestamp < $1.timestamp }
        var pairs: [BossHealPair] = []

        for bossCast in bossCasts {
            // 보스 스킬 시전 직후 30초 이내 힐러 스킬 중 가장 빠른 것
            let windowUpperBound = bossCast.timestamp + 30_000
            for healCast in sortedHealerCasts {
                if healCast.timestamp > windowUpperBound { break }
                if healCast.timestamp < bossCast.timestamp { continue }
                let delaySeconds = Double(healCast.timestamp - bossCast.timestamp) / 1000.0
                pairs.append(BossHealPair(
                    encounterID:   encounterID,
                    bossSpellID:   bossCast.spellID,
                    healSpellID:   healCast.spellID,
                    delaySeconds:  delaySeconds
                ))
                break
            }
        }

        return pairs
    }

    private func updateProgress(total: Int, completed: Int, name: String) {
        state = .collecting(RankerCollectionProgress(
            total: total, completed: completed, currentName: name
        ))
    }

    private func errorMessage(_ error: Error) -> String {
        if let appError = error as? AppError {
            return appError.errorDescription ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    private func isoStringKST() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter.string(from: Date())
    }

    var canSaveToFile: Bool { !wowAddonsPath.isEmpty }

    var availablePresets: [TalentPreset] {
        TalentPresetCatalog.presets(for: selectedSpec)
    }

    var availableDungeons: [DungeonInfo] {
        switch selectedDifficulty {
        case .mythicPlus:
            return DungeonInfo.currentSeason
        case .heroic, .normal:
            return DungeonInfo.currentSeason.filter { $0.supportsNormalHeroic }
        }
    }

    func resetDungeonSelectionIfNeeded() {
        guard let current = selectedDungeon else { return }
        if !availableDungeons.contains(current) {
            selectedDungeon = availableDungeons.first
        }
    }
}
