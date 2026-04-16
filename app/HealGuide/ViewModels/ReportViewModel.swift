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
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "ReportViewModel")

    init(
        urlParser: any URLParsing,
        keychain: any KeychainStoring,
        apiClient: any WarcraftLogsAPIClient,
        normalizer: any TimelineNormalizing,
        luaGenerator: any LuaGenerating,
        pasteboard: any PasteboardWriting,
        spellResolver: any SpellResolving
    ) {
        self.urlParser = urlParser
        self.keychain = keychain
        self.apiClient = apiClient
        self.normalizer = normalizer
        self.luaGenerator = luaGenerator
        self.pasteboard = pasteboard
        self.spellResolver = spellResolver
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
        let catalog = spellResolver.spells(for: spec)
        selectedSpellIDs = Set(catalog.map(\.id))
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

        // 카탈로그에 없는 주문 탐지
        let catalogIDs = Set(spellResolver.allSpellIDs(for: spec))
        let unknown = Array(allPlayerSpellIDs.subtracting(catalogIDs)).sorted()

        let luaText = luaGenerator.generate(
            blocks: blocks,
            metadata: ExportMetadata(
                spec: spec,
                dungeonName: dungeonName,
                sourceURL: reportURLText,
                generatedAt: Date()
            )
        )
        state = .success(LuaOutput(blocks: blocks, luaText: luaText), unknownSpellIDs: unknown)
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
