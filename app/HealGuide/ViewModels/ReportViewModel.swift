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

        let fightMeta: FightMeta
        do {
            fightMeta = try await apiClient.fetchFight(
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

        let playerCasts: [CastEvent]
        let bossCasts: [CastEvent]
        do {
            async let playerFetch = apiClient.fetchCasts(
                reportCode: reportURL.code,
                fightID: reportURL.fightID,
                sourceID: reportURL.sourceID,
                hostilityType: .friendly,
                token: token
            )
            async let bossFetch = apiClient.fetchCasts(
                reportCode: reportURL.code,
                fightID: reportURL.fightID,
                sourceID: nil,
                hostilityType: .hostile,
                token: token
            )
            playerCasts = try await playerFetch
            bossCasts = try await bossFetch
        } catch let error as AppError {
            state = .failure(error)
            return
        } catch {
            state = .failure(.networkError(error.localizedDescription))
            return
        }

        let entries = normalizer.normalize(
            playerCasts: playerCasts,
            bossCasts: bossCasts,
            windowSeconds: 30.0
        )

        let output = luaGenerator.generate(
            entries: entries,
            spec: selectedSpec,
            encounterID: fightMeta.encounterID
        )

        state = .success(output)
    }
}
