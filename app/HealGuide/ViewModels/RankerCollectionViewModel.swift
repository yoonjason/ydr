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

    // MARK: - Dependencies

    private let apiClient:      any WarcraftLogsAPIClient
    private let rankingService: any CharacterRankingsService
    private let filterService:  any TalentFilterService
    private let merger:         any RankerDataMerger
    private let serializer:     RankerLuaSerializer
    private let cacheService:   RankerCacheService
    private let keychain:       any KeychainStoring
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "RankerVM")

    private var suppressPersist: Bool = false

    init(
        apiClient:      any WarcraftLogsAPIClient      = WarcraftLogsAPIClientImpl(),
        rankingService: any CharacterRankingsService   = CharacterRankingsServiceImpl(),
        filterService:  any TalentFilterService        = TalentFilterServiceImpl(),
        merger:         any RankerDataMerger           = RankerDataMergerImpl(),
        keychain:       any KeychainStoring            = FileCredentialStore(),
        cacheService:   RankerCacheService             = RankerCacheService()
    ) {
        self.apiClient      = apiClient
        self.rankingService = rankingService
        self.filterService  = filterService
        self.merger         = merger
        self.keychain       = keychain
        self.cacheService   = cacheService
        self.serializer     = RankerLuaSerializer()
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

    func collect() async {
        guard let dungeon = selectedDungeon else { return }
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            state = .failure("WarcraftLogs Client ID / Secret 을 입력해주세요.")
            return
        }

        state = .collecting(RankerCollectionProgress(total: topNCount.rawValue, completed: 0, currentName: "인증 중..."))

        // 1. 액세스 토큰
        let token: String
        do {
            token = try await apiClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
        } catch {
            state = .failure("액세스 토큰 발급 실패: \(errorMessage(error))")
            return
        }

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
            state = .failure("characterRankings 조회 실패: \(errorMessage(error))")
            return
        }

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

        // 4. 각 파스의 보스→힐 쌍 수집
        let totalFiltered = filteredParses.count
        var parseResults: [(parse: RankerParse, bossPairs: [BossHealPair])] = []

        for (index, parse) in filteredParses.enumerated() {
            updateProgress(total: totalFiltered, completed: index, name: "\(parse.characterName) 처리 중...")

            do {
                let pairs = try await fetchBossPairs(
                    parse: parse, spec: selectedSpec, token: token
                )
                parseResults.append((parse: parse, bossPairs: pairs))
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

        let merged  = merger.merge(parses: parseResults, meta: meta)
        let preview = merger.buildPreview(
            parsesCollected: rawParses.count,
            parsesFiltered:  parseResults.count,
            data:            merged
        )

        state = .preview(preview, merged)
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
            logger.info("HGPT_RankerData.lua 저장: \(filePath) (\(entries.count) entries)")
        } catch {
            lastSaveResult = "저장 실패: \(error.localizedDescription)"
            logger.error("HGPT_RankerData.lua 저장 실패: \(error)")
        }
    }

    // MARK: - 초기화

    func reset() {
        state           = .idle
        lastSaveResult  = nil
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
    ) async throws -> [BossHealPair] {
        // 보스 윈도우 + 힐러 sourceID 병렬 조회
        async let encounterFetch = apiClient.fetchEncounters(
            reportCode: parse.reportCode, fightID: parse.fightID, token: token
        )
        async let playerFetch = apiClient.fetchPlayerDetails(
            reportCode: parse.reportCode, fightID: parse.fightID, token: token
        )
        let (encounter, players) = try await (encounterFetch, playerFetch)

        // 대상 힐러 sourceID 탐색 (스펙 매칭)
        let matchingHealer = players.first { candidate in
            candidate.className  == spec.warcraftLogsClassName &&
            candidate.specName   == spec.warcraftLogsSpecName
        } ?? players.first { $0.healerSpec != nil }

        guard let healerCandidate = matchingHealer else { return [] }

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

        return allPairs
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
