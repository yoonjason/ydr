import Foundation
import os

@MainActor
final class ReportViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case detectingHealers
        case healerSelection(healers: [HealerCandidate], dungeonName: String)
        case spellSelection(healer: HealerCandidate)
        case generating
        case success(LuaOutput, unknownSpellIDs: [Int])
        case failure(AppError)
    }

    @Published var reportURLText: String = ""
    @Published var clientID: String = "" {
        didSet { persistClientID() }
    }
    @Published var clientSecret: String = "" {
        didSet { persistClientSecret() }
    }
    @Published var isSecretVisible: Bool = false
    @Published private(set) var state: ViewState = .idle
    @Published var wowAddonsPath: String = "" {
        didSet { persistWowAddonsPath() }
    }
    @Published var wtfCharacterPath: String = "" {
        didSet { persistWtfCharacterPath() }
    }
    @Published var lastSaveResult: String?
    @Published var combatHistory: [CombatRecord] = []

    private var suppressPersist: Bool = false

    private func persistClientID() {
        guard !suppressPersist, !clientID.isEmpty else { return }
        do { try keychain.saveClientID(clientID) }
        catch { logger.error("persist clientID failed: \(error)") }
    }

    private func persistClientSecret() {
        guard !suppressPersist, !clientSecret.isEmpty else { return }
        do { try keychain.save(clientSecret) }
        catch { logger.error("persist secret failed: \(error)") }
    }

    private func persistBlizzardClientID() {
        guard !suppressPersist, !blizzardClientID.isEmpty else { return }
        do { try blizzardKeychain.saveClientID(blizzardClientID) }
        catch { logger.error("persist blizzard clientID failed: \(error)") }
    }

    private func persistBlizzardClientSecret() {
        guard !suppressPersist, !blizzardClientSecret.isEmpty else { return }
        do { try blizzardKeychain.save(blizzardClientSecret) }
        catch { logger.error("persist blizzard secret failed: \(error)") }
    }

    // 힐러 선택 / 주문 선택 상태
    @Published var selectedHealerID: Int?
    @Published var selectedSpellIDs: Set<Int> = []

    // 플로우 사이 캐싱
    private var cachedToken: String?
    private var cachedReportURL: ReportURL?
    private var cachedBossWindows: [BossWindow] = []
    private var cachedDungeonName: String = ""
    private var cachedHealers: [HealerCandidate] = []

    private let urlParser: any URLParsing
    private let keychain: any KeychainStoring
    private let apiClient: any WarcraftLogsAPIClient
    private let normalizer: any TimelineNormalizing
    private let luaGenerator: any LuaGenerating
    private let pasteboard: any PasteboardWriting
    private let spellResolver: any SpellResolving
    private let spellCatalogStore: any SpellCatalogStoring
    private let blizzardKeychain: any KeychainStoring
    private let blizzardAPIClient: any BlizzardGameDataAPIClient
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "ReportViewModel")

    @Published var blizzardClientID: String = "" {
        didSet { persistBlizzardClientID() }
    }
    @Published var blizzardClientSecret: String = "" {
        didSet { persistBlizzardClientSecret() }
    }
    @Published var isBlizzardSecretVisible: Bool = false
    @Published var discoveredSpells: [DiscoveredSpell] = []
    @Published var showNewSpellSheet = false
    @Published var isResolvingBlizzardNames = false

    var hasBlizzardCredentials: Bool {
        !blizzardClientID.isEmpty && !blizzardClientSecret.isEmpty
    }

    init(
        urlParser: any URLParsing,
        keychain: any KeychainStoring,
        apiClient: any WarcraftLogsAPIClient,
        normalizer: any TimelineNormalizing,
        luaGenerator: any LuaGenerating,
        pasteboard: any PasteboardWriting,
        spellResolver: any SpellResolving,
        spellCatalogStore: any SpellCatalogStoring = SpellCatalogStore(),
        blizzardKeychain: any KeychainStoring = FileCredentialStore(fileName: "blizzard_credentials.json"),
        blizzardAPIClient: any BlizzardGameDataAPIClient = BlizzardGameDataAPIClientImpl()
    ) {
        self.urlParser = urlParser
        self.keychain = keychain
        self.apiClient = apiClient
        self.normalizer = normalizer
        self.luaGenerator = luaGenerator
        self.pasteboard = pasteboard
        self.spellResolver = spellResolver
        self.spellCatalogStore = spellCatalogStore
        self.blizzardKeychain = blizzardKeychain
        self.blizzardAPIClient = blizzardAPIClient
    }

    func onAppear() {
        suppressPersist = true
        defer { suppressPersist = false }
        if clientSecret.isEmpty, let secret = keychain.load() {
            clientSecret = secret
        }
        if clientID.isEmpty, let id = keychain.loadClientID() {
            clientID = id
        }
        if blizzardClientID.isEmpty, let id = blizzardKeychain.loadClientID() {
            blizzardClientID = id
        }
        if blizzardClientSecret.isEmpty, let secret = blizzardKeychain.load() {
            blizzardClientSecret = secret
        }
        if wowAddonsPath.isEmpty {
            wowAddonsPath = UserDefaults.standard.string(forKey: "wowAddonsPath") ?? ""
        }
        if wtfCharacterPath.isEmpty {
            wtfCharacterPath = UserDefaults.standard.string(forKey: "wtfCharacterPath") ?? ""
        }
        refreshBaselineIfNeeded()
    }

    private func persistWowAddonsPath() {
        guard !suppressPersist else { return }
        UserDefaults.standard.set(wowAddonsPath, forKey: "wowAddonsPath")
    }

    private func persistWtfCharacterPath() {
        guard !suppressPersist else { return }
        UserDefaults.standard.set(wtfCharacterPath, forKey: "wtfCharacterPath")
    }

    var canSaveToFile: Bool { !wowAddonsPath.isEmpty }
    var canSaveToSavedVariables: Bool { !wtfCharacterPath.isEmpty }

    func saveToFile() {
        guard case .success(let output, _) = state else { return }
        let directory = (wowAddonsPath as NSString).appendingPathComponent("HealGuide/Data")
        let filePath = (directory as NSString).appendingPathComponent("HealGuide_Generated.lua")

        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            // 첫 줄 "return {" 만 정확히 한 번 교체 (offset 기반보다 명확).
            let fileContent: String
            if output.luaText.hasPrefix("return {") {
                fileContent = "HealGuide_Generated = {" + output.luaText.dropFirst("return {".count)
            } else {
                fileContent = output.luaText
            }
            try fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            lastSaveResult = "저장 완료: \(filePath)"
            logger.info("Lua 파일 저장: \(filePath)")
        } catch {
            lastSaveResult = "저장 실패: \(error.localizedDescription)"
            logger.error("Lua 파일 저장 실패: \(error)")
        }
    }

    func saveToSavedVariables() {
        guard case .success(let output, _) = state else { return }
        guard let reportURL = cachedReportURL,
              let healer = cachedHealers.first(where: { $0.id == selectedHealerID }),
              let spec = healer.healerSpec else { return }

        let writer = SavedVariablesWriter()
        do {
            try writer.writeToSavedVariables(
                wtfCharacterPath: wtfCharacterPath,
                blocks: output.blocks,
                spec: spec,
                dungeonName: cachedDungeonName,
                sourceURL: reportURLText
            )
            lastSaveResult = "SavedVariables 저장 완료 (다음 로그인 시 적용)"
        } catch {
            lastSaveResult = "SavedVariables 저장 실패: \(error.localizedDescription)"
            logger.error("SavedVariables 저장 실패: \(error)")
        }
    }

    func refreshBaselineIfNeeded() {
        guard hasBlizzardCredentials else { return }
        Task { await performBaselineRefresh() }
    }

    private func performBaselineRefresh() async {
        do {
            let token = try await blizzardAPIClient.fetchAccessToken(
                clientID: blizzardClientID, clientSecret: blizzardClientSecret
            )
            // mutable: 세션 내에서 이미 처리한 ID 추적해 이중 해상 방지
            var knownIDs = spellCatalogStore.knownSpellIDs()
            let now = Date()
            var newRecords: [SpellCatalogRecord] = []

            // Blizzard Playable Spec API 기반 탐색
            for spec in HealerSpec.allCases {
                let specInfo = try? await blizzardAPIClient.fetchPlayableSpecialization(
                    specID: spec.blizzardSpecID, token: token
                )
                guard let spellIDs = specInfo?.spellIDs else { continue }
                for spellID in spellIDs where !knownIDs.contains(spellID) {
                    newRecords.append(await resolveSpellRecord(spellID: spellID, source: .blizzardAPI, token: token, now: now))
                    knownIDs.insert(spellID)
                }
            }

            // 하드코딩 카탈로그 스킬 중 아직 이름 없는 것 해상
            let allCatalogIDs = Set(HealerSpec.allCases.flatMap { SpecSpellCatalog.spellIDs(for: $0) })
            for spellID in allCatalogIDs.subtracting(knownIDs) {
                newRecords.append(await resolveSpellRecord(spellID: spellID, source: .baseline, token: token, now: now))
            }

            if !newRecords.isEmpty {
                try? spellCatalogStore.upsertMany(newRecords)
                logger.info("베이스라인 갱신 완료: \(newRecords.count)개 스킬")
            }
        } catch {
            logger.warning("베이스라인 갱신 실패: \(error)")
        }
    }

    private func resolveSpellRecord(
        spellID: Int,
        source: SpellCatalogRecord.Source,
        token: String,
        now: Date
    ) async -> SpellCatalogRecord {
        let krName: String
        if let info = try? await blizzardAPIClient.fetchSpell(spellID: spellID, locale: "ko_KR", token: token) {
            krName = info.name
        } else {
            krName = "Spell #\(spellID)"
        }
        let enName: String
        if let info = try? await blizzardAPIClient.fetchSpell(spellID: spellID, locale: "en_US", token: token) {
            enName = info.name
        } else {
            enName = "Spell #\(spellID)"
        }
        return SpellCatalogRecord(spellID: spellID, nameKR: krName, nameEN: enName, firstSeenAt: now, source: source)
    }

    func loadCombatHistory() {
        guard !wtfCharacterPath.isEmpty else { return }
        let reader = CombatHistoryReader()
        combatHistory = reader.read(wtfCharacterPath: wtfCharacterPath)
    }

    func copyToClipboard() {
        guard case .success(let output, _) = state else { return }
        pasteboard.write(output.luaText)
    }

    func resolvedSpells(for spec: HealerSpec) -> [SpellEntry] {
        spellResolver.spells(for: spec)
    }

    // MARK: - Stage 1: 힐러 감지

    func detectHealers() async {
        if case .detectingHealers = state { return }
        state = .detectingHealers

        let reportURL: ReportURL
        do {
            reportURL = try urlParser.parse(reportURLText)
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.invalidURL)
            return
        }

        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            state = .failure(.authenticationFailed)
            return
        }

        do { try keychain.save(clientSecret) } catch { logger.error("Keychain save secret failed: \(error)") }
        do { try keychain.saveClientID(clientID) } catch { logger.error("Keychain save clientID failed: \(error)") }

        let token: String
        do {
            token = try await apiClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        // fetchEncounters 과 fetchPlayerDetails 병렬
        let dungeonName: String
        let bossWindows: [BossWindow]
        let healers: [HealerCandidate]
        do {
            async let encountersFetch = apiClient.fetchEncounters(
                reportCode: reportURL.code, fightID: reportURL.fightID, token: token
            )
            async let playersFetch = apiClient.fetchPlayerDetails(
                reportCode: reportURL.code, fightID: reportURL.fightID, token: token
            )
            let (enc, players) = try await (encountersFetch, playersFetch)
            dungeonName = enc.dungeonName
            bossWindows = enc.windows
            healers = players
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        // 힐러로 매핑 가능한 후보만 필터
        let mappable = healers.filter { $0.healerSpec != nil }
        guard !mappable.isEmpty else {
            state = .failure(.noHealers)
            return
        }

        cachedToken = token
        cachedReportURL = reportURL
        cachedBossWindows = bossWindows
        cachedDungeonName = dungeonName
        cachedHealers = mappable

        // URL 의 source 와 일치하는 힐러가 있으면 자동 선택하고 주문 선택 단계로 진행
        let urlSource = reportURL.sourceID
        if mappable.contains(where: { $0.id == urlSource }) {
            selectedHealerID = urlSource
            advanceToSpellSelection()
        } else {
            selectedHealerID = mappable.first?.id
            state = .healerSelection(healers: mappable, dungeonName: dungeonName)
        }
    }

    // MARK: - Stage 2: 힐러 선택 → 주문 선택

    func confirmHealerSelection() {
        advanceToSpellSelection()
    }

    private func advanceToSpellSelection() {
        guard let selectedID = selectedHealerID,
              let healer = cachedHealers.first(where: { $0.id == selectedID }),
              let spec = healer.healerSpec else {
            state = .failure(.noHealers)
            return
        }
        selectedSpellIDs = []
        state = .spellSelection(healer: healer)
    }

    func toggleSpell(_ spellID: Int) {
        if selectedSpellIDs.contains(spellID) {
            selectedSpellIDs.remove(spellID)
        } else {
            selectedSpellIDs.insert(spellID)
        }
    }

    func checkAllSpells() {
        guard case .spellSelection(let healer) = state, let spec = healer.healerSpec else { return }
        selectedSpellIDs = Set(spellResolver.spells(for: spec).map(\.id))
    }

    func uncheckAllSpells() {
        selectedSpellIDs = []
    }

    // MARK: - Stage 3: Lua 생성

    func generate() async {
        guard case .spellSelection(let healer) = state,
              let token = cachedToken,
              let reportURL = cachedReportURL,
              let spec = healer.healerSpec else {
            state = .failure(.authenticationFailed)
            return
        }
        let sourceID = healer.id
        let bossWindows = cachedBossWindows
        let dungeonName = cachedDungeonName
        let includedSpellIDs = selectedSpellIDs

        state = .generating

        var blocks: [EncounterBlock] = []
        var allPlayerSpellIDs = Set<Int>()

        do {
            var results: [(startTime: Int64, block: EncounterBlock, playerSpellIDs: Set<Int>)] = []
            try await withThrowingTaskGroup(of: (Int64, EncounterBlock, Set<Int>).self) { group in
                for window in bossWindows {
                    group.addTask {
                        async let playerFetch = self.apiClient.fetchCasts(
                            reportCode: reportURL.code,
                            fightID: reportURL.fightID,
                            sourceID: sourceID,
                            hostilityType: .friendly,
                            startTime: window.startTime,
                            endTime: window.endTime,
                            token: token
                        )
                        async let bossFetch = self.apiClient.fetchCasts(
                            reportCode: reportURL.code,
                            fightID: reportURL.fightID,
                            sourceID: nil,
                            hostilityType: .hostile,
                            startTime: window.startTime,
                            endTime: window.endTime,
                            token: token
                        )
                        let (playerCasts, bossCasts) = try await (playerFetch, bossFetch)
                        let observedSpellIDs = Set(playerCasts.map(\.spellID))

                        // 선택된 주문만 필터
                        let filteredPlayerCasts = playerCasts.filter { includedSpellIDs.contains($0.spellID) }

                        let (absolute, reactions, leadIns) = self.normalizer.normalize(
                            encounterStart: window.startTime,
                            encounterEnd: window.endTime,
                            bossCasts: bossCasts,
                            playerCasts: filteredPlayerCasts,
                            maxWindow: 30.0
                        )
                        let duration = Double(window.endTime - window.startTime) / 1000.0
                        let block = EncounterBlock(
                            encounterID: window.encounterID,
                            name: window.name,
                            duration: duration,
                            absolute: absolute,
                            reactions: reactions,
                            leadIns: leadIns
                        )
                        return (window.startTime, block, observedSpellIDs)
                    }
                }
                for try await result in group {
                    results.append((startTime: result.0, block: result.1, playerSpellIDs: result.2))
                }
            }
            blocks = results.sorted { $0.startTime < $1.startTime }.map { $0.block }
            for r in results { allPlayerSpellIDs.formUnion(r.playerSpellIDs) }
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        let catalogIDs = Set(spellResolver.allSpellIDs(for: spec))
        let unknownIDs = Array(allPlayerSpellIDs.subtracting(catalogIDs)).sorted()

        let encounterData = await fetchEncounterData(
            encounterIDs: bossWindows.map(\.encounterID)
        )

        let luaText = luaGenerator.generate(
            blocks: blocks,
            metadata: ExportMetadata(
                spec: spec,
                dungeonName: dungeonName,
                sourceURL: reportURLText,
                generatedAt: Date(),
                bossSpellNames: encounterData.bossSpellNames
            )
        )

        state = .success(
            LuaOutput(blocks: blocks, luaText: luaText, bossNameMap: encounterData.encounterNames),
            unknownSpellIDs: unknownIDs
        )

        if !unknownIDs.isEmpty {
            await resolveUnknownSpells(unknownIDs, reportCode: reportURL.code, token: token)
        }
    }

    // MARK: - 보스/인카운터 이름 해상

    struct EncounterNamesResult {
        var bossSpellNames: [Int: String] = [:]
        var encounterNames: [Int: String] = [:]
    }

    private func fetchEncounterData(encounterIDs: [Int]) async -> EncounterNamesResult {
        guard hasBlizzardCredentials else { return EncounterNamesResult() }
        var result = EncounterNamesResult()
        do {
            let token = try await blizzardAPIClient.fetchAccessToken(
                clientID: blizzardClientID, clientSecret: blizzardClientSecret
            )
            for encounterID in Set(encounterIDs) {
                if let encounter = try? await blizzardAPIClient.fetchJournalEncounter(
                    encounterID: encounterID, locale: "ko_KR", token: token
                ) {
                    result.encounterNames[encounterID] = encounter.name
                    for ability in encounter.abilities {
                        result.bossSpellNames[ability.spellID] = ability.name
                    }
                }
            }
        } catch {
            logger.warning("인카운터/스킬 이름 해상 실패: \(error)")
        }
        return result
    }

    // MARK: - 신규 스킬 감지

    private func resolveUnknownSpells(_ unknownIDs: [Int], reportCode: String, token: String) async {
        var nameMap: [Int: String] = [:]
        do {
            let abilities = try await apiClient.fetchMasterData(reportCode: reportCode, token: token)
            for ability in abilities where unknownIDs.contains(ability.gameID) {
                nameMap[ability.gameID] = ability.name
            }
        } catch {
            logger.warning("masterData fetch 실패, spellID 만 표시: \(error)")
        }

        discoveredSpells = unknownIDs.map { id in
            DiscoveredSpell(
                spellID: id,
                name: nameMap[id] ?? "Spell #\(id)"
            )
        }
        showNewSpellSheet = true
    }

    func toggleDiscoveredSpell(_ spellID: Int) {
        guard let index = discoveredSpells.firstIndex(where: { $0.id == spellID }) else { return }
        discoveredSpells[index].selected.toggle()
    }

    func selectAllDiscoveredSpells() {
        for index in discoveredSpells.indices { discoveredSpells[index].selected = true }
    }

    func approveDiscoveredSpells() {
        let approved = discoveredSpells.filter(\.selected)
        guard !approved.isEmpty else {
            showNewSpellSheet = false
            discoveredSpells = []
            return
        }

        if hasBlizzardCredentials {
            Task { await approveWithBlizzardNames(approved) }
        } else {
            let records = approved.map { spell in
                SpellCatalogRecord(
                    spellID: spell.id,
                    nameKR: spell.name,
                    nameEN: spell.name,
                    firstSeenAt: Date(),
                    source: .wclMasterData
                )
            }
            try? spellCatalogStore.upsertMany(records)
            showNewSpellSheet = false
            discoveredSpells = []
        }
    }

    private func approveWithBlizzardNames(_ approved: [DiscoveredSpell]) async {
        isResolvingBlizzardNames = true
        var records: [SpellCatalogRecord] = []
        let now = Date()

        do {
            let token = try await blizzardAPIClient.fetchAccessToken(
                clientID: blizzardClientID,
                clientSecret: blizzardClientSecret
            )

            for spell in approved {
                var nameKR = spell.name
                var nameEN = spell.name
                var source: SpellCatalogRecord.Source = .wclMasterData

                if let krInfo = try? await blizzardAPIClient.fetchSpell(
                    spellID: spell.id, locale: "ko_KR", token: token
                ) {
                    nameKR = krInfo.name
                    source = .blizzardAPI
                }
                if let enInfo = try? await blizzardAPIClient.fetchSpell(
                    spellID: spell.id, locale: "en_US", token: token
                ) {
                    nameEN = enInfo.name
                }
                let iconURL = try? await blizzardAPIClient.fetchSpellMedia(
                    spellID: spell.id, token: token
                )

                records.append(SpellCatalogRecord(
                    spellID: spell.id,
                    nameKR: nameKR,
                    nameEN: nameEN,
                    iconURL: iconURL,
                    firstSeenAt: now,
                    source: source
                ))
            }
        } catch {
            logger.warning("Blizzard API 인증 실패, WCL 이름으로 저장: \(error)")
            records = approved.map { spell in
                SpellCatalogRecord(
                    spellID: spell.id,
                    nameKR: spell.name,
                    nameEN: spell.name,
                    firstSeenAt: now,
                    source: .wclMasterData
                )
            }
        }

        try? spellCatalogStore.upsertMany(records)
        isResolvingBlizzardNames = false
        showNewSpellSheet = false
        discoveredSpells = []
    }

    func dismissDiscoveredSpells() {
        showNewSpellSheet = false
        discoveredSpells = []
    }

    // MARK: - 되돌리기

    func resetToIdle() {
        state = .idle
        selectedHealerID = nil
        selectedSpellIDs = []
        cachedToken = nil
        cachedReportURL = nil
        cachedBossWindows = []
        cachedDungeonName = ""
        cachedHealers = []
    }

    func backToHealerSelection() {
        guard !cachedHealers.isEmpty else {
            resetToIdle()
            return
        }
        state = .healerSelection(healers: cachedHealers, dungeonName: cachedDungeonName)
    }
}
