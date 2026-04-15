import Foundation
import os

@MainActor
final class ReportViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case fetching
        case success(LuaOutput)
        case failure(AppError)
    }

    @Published var reportURLText: String = ""
    @Published var clientID: String = ""
    @Published var clientSecret: String = ""
    @Published var selectedSpec: HealerSpec = .discPriest
    @Published var isSecretVisible: Bool = false
    @Published private(set) var state: ViewState = .idle

    private let urlParser: any URLParsing
    private let keychain: any KeychainStoring
    private let apiClient: any WarcraftLogsAPIClient
    private let normalizer: any TimelineNormalizing
    private let luaGenerator: any LuaGenerating
    private let pasteboard: any PasteboardWriting
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "ReportViewModel")

    init(
        urlParser: any URLParsing,
        keychain: any KeychainStoring,
        apiClient: any WarcraftLogsAPIClient,
        normalizer: any TimelineNormalizing,
        luaGenerator: any LuaGenerating,
        pasteboard: any PasteboardWriting
    ) {
        self.urlParser = urlParser
        self.keychain = keychain
        self.apiClient = apiClient
        self.normalizer = normalizer
        self.luaGenerator = luaGenerator
        self.pasteboard = pasteboard
    }

    func onAppear() {
        if clientSecret.isEmpty, let secret = keychain.load() {
            clientSecret = secret
        }
        if clientID.isEmpty, let id = keychain.loadClientID() {
            clientID = id
        }
    }

    func copyToClipboard() {
        guard case .success(let output) = state else { return }
        pasteboard.write(output.luaText)
    }

    func fetchFight() async {
        guard state != .fetching else { return }
        state = .fetching

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

        do {
            try keychain.save(clientSecret)
        } catch {
            logger.error("Keychain save secret failed: \(error)")
        }
        do {
            try keychain.saveClientID(clientID)
        } catch {
            logger.error("Keychain save clientID failed: \(error)")
        }

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

        do {
            // fight 존재 여부 사전 검증 — 결과 불필요
            _ = try await apiClient.fetchFight(
                reportCode: reportURL.code,
                fightID: reportURL.fightID,
                token: token
            )
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        let bossWindows: [BossWindow]
        do {
            bossWindows = try await apiClient.fetchEncounters(
                reportCode: reportURL.code,
                fightID: reportURL.fightID,
                token: token
            )
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        guard !bossWindows.isEmpty else {
            state = .failure(.noBossEncounters)
            return
        }

        var blocks: [EncounterBlock] = []
        do {
            var results: [(startTime: Int64, block: EncounterBlock)] = []
            try await withThrowingTaskGroup(of: (Int64, EncounterBlock).self) { group in
                for window in bossWindows {
                    group.addTask {
                        async let playerFetch = self.apiClient.fetchCasts(
                            reportCode: reportURL.code,
                            fightID: reportURL.fightID,
                            sourceID: reportURL.sourceID,
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

                        let (absolute, reactions) = self.normalizer.normalize(
                            encounterStart: window.startTime,
                            encounterEnd: window.endTime,
                            bossCasts: bossCasts,
                            playerCasts: playerCasts,
                            maxWindow: 30.0
                        )
                        let duration = Double(window.endTime - window.startTime) / 1000.0
                        let block = EncounterBlock(
                            encounterID: window.encounterID,
                            name: window.name,
                            duration: duration,
                            absolute: absolute,
                            reactions: reactions
                        )
                        return (window.startTime, block)
                    }
                }
                for try await result in group {
                    results.append((startTime: result.0, block: result.1))
                }
            }
            blocks = results.sorted { $0.startTime < $1.startTime }.map { $0.block }
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        let luaText = luaGenerator.generate(
            blocks: blocks,
            metadata: ExportMetadata(spec: selectedSpec)
        )
        state = .success(LuaOutput(blocks: blocks, luaText: luaText))
    }
}
