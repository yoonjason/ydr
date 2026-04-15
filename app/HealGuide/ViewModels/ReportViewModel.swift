import Foundation
import os

@MainActor
final class ReportViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case fetching
        case success(FightMeta)
        case failure(AppError)
    }

    @Published var reportURLText: String = ""
    @Published var clientID: String = ""
    @Published var clientSecret: String = ""
    @Published var selectedSpec: HealerSpec = .discPriest
    @Published private(set) var state: ViewState = .idle

    private let urlParser: any URLParsing
    private let keychain: any KeychainStoring
    private let apiClient: any WarcraftLogsAPIClient
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "ReportViewModel")

    init(
        urlParser: any URLParsing,
        keychain: any KeychainStoring,
        apiClient: any WarcraftLogsAPIClient
    ) {
        self.urlParser = urlParser
        self.keychain = keychain
        self.apiClient = apiClient
    }

    func onAppear() {
        if let secret = keychain.load() {
            clientSecret = secret
        }
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
            logger.error("Keychain save failed: \(error)")
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
            let meta = try await apiClient.fetchFight(
                reportCode: reportURL.code,
                fightID: reportURL.fightID,
                token: token
            )
            state = .success(meta)
        } catch let error as AppError {
            state = .failure(error)
        } catch {
            state = .failure(.networkError(error.localizedDescription))
        }
    }
}
