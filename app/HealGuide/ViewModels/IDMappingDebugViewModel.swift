import Foundation
import os

@MainActor
final class IDMappingDebugViewModel: ObservableObject {

    // MARK: - Input

    @Published var wclClientID:     String = ""
    @Published var wclClientSecret: String = ""
    @Published var blizzardClientID:     String = ""
    @Published var blizzardClientSecret: String = ""

    @Published var wclEncounterID:      String = "12805"   // Windrunner Spire (WCL)
    @Published var cmMapID:             String = "2805"    // CM mapID
    @Published var journalEncounterID:  String = "2562"    // 핸드오프에서 잘못 박힌 ID 중 하나
    @Published var journalInstanceID:   String = "1273"    // Nerub'ar Palace (레이드) 예시

    // MARK: - Output

    @Published private(set) var resultLog: String = ""
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var currentAction: String = ""

    // MARK: - Dependencies

    private let wclClient:        any WarcraftLogsAPIClient
    private let blizzardClient:   any BlizzardGameDataAPIClient
    private let wclKeychain:      any KeychainStoring
    private let blizzardKeychain: any KeychainStoring
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "IDMappingDebug")

    init(
        wclClient:        any WarcraftLogsAPIClient    = WarcraftLogsAPIClientImpl(),
        blizzardClient:   any BlizzardGameDataAPIClient = BlizzardGameDataAPIClientImpl(),
        wclKeychain:      any KeychainStoring          = FileCredentialStore(),
        blizzardKeychain: any KeychainStoring          = FileCredentialStore(fileName: "blizzard_credentials.json")
    ) {
        self.wclClient = wclClient
        self.blizzardClient = blizzardClient
        self.wclKeychain = wclKeychain
        self.blizzardKeychain = blizzardKeychain
    }

    func onAppear() {
        if wclClientID.isEmpty, let id = wclKeychain.loadClientID() { wclClientID = id }
        if wclClientSecret.isEmpty, let s = wclKeychain.load() { wclClientSecret = s }
        if blizzardClientID.isEmpty, let id = blizzardKeychain.loadClientID() { blizzardClientID = id }
        if blizzardClientSecret.isEmpty, let s = blizzardKeychain.load() { blizzardClientSecret = s }
    }

    func clearResults() {
        resultLog = ""
    }

    // MARK: - Queries

    func queryWCLEncounterName() async {
        await withQuery(action: "WCL encounter name 조회") {
            guard let id = Int(self.wclEncounterID) else {
                return "❌ WCL encID 숫자 변환 실패"
            }
            guard !self.wclClientID.isEmpty, !self.wclClientSecret.isEmpty else {
                return "❌ WCL 자격증명 없음"
            }
            let token = try await self.wclClient.fetchAccessToken(
                clientID: self.wclClientID, clientSecret: self.wclClientSecret
            )
            let name = try await self.wclClient.fetchEncounterName(encounterID: id, token: token)
            return "🔵 WCL worldData.encounter(id: \(id)).name\n→ name = \(name ?? "<nil>")"
        }
    }

    func queryBlizzardJournalEncounter() async {
        await withQuery(action: "Blizzard journal-encounter/{WCL encID}") {
            guard let id = Int(self.wclEncounterID) else {
                return "❌ WCL encID 숫자 변환 실패"
            }
            let token = try await self.fetchBlizzardToken()
            let result = try await self.blizzardClient.fetchJournalEncounter(
                encounterID: id, locale: "ko_KR", token: token
            )
            let abilitiesPreview = result.abilities.prefix(5)
                .map { "  - \($0.spellID) / \($0.name)" }
                .joined(separator: "\n")
            return """
            🟠 Blizzard /data/wow/journal-encounter/\(id)?locale=ko_KR
            → name = \(result.name)
            → abilities (앞 5개):
            \(abilitiesPreview.isEmpty ? "  (없음)" : abilitiesPreview)
            """
        }
    }

    func queryBlizzardJournalEncounterForJournalID() async {
        await withQuery(action: "Blizzard journal-encounter/{journalEncounterID}") {
            guard let id = Int(self.journalEncounterID) else {
                return "❌ journalEncounterID 숫자 변환 실패"
            }
            let token = try await self.fetchBlizzardToken()
            let result = try await self.blizzardClient.fetchJournalEncounter(
                encounterID: id, locale: "ko_KR", token: token
            )
            return "🟠 Blizzard /data/wow/journal-encounter/\(id)?locale=ko_KR\n→ name = \(result.name)\n→ abilities count = \(result.abilities.count)"
        }
    }

    func queryBlizzardJournalInstance() async {
        await withQuery(action: "Blizzard journal-instance/{id}") {
            guard let id = Int(self.journalInstanceID) else {
                return "❌ journalInstanceID 숫자 변환 실패"
            }
            let token = try await self.fetchBlizzardToken()
            let info = try await self.blizzardClient.fetchJournalInstance(
                instanceID: id, locale: "ko_KR", token: token
            )
            let encs = info.encounters
                .map { "  - \($0.encounterID) / \($0.name)" }
                .joined(separator: "\n")
            return """
            🟣 Blizzard /data/wow/journal-instance/\(id)?locale=ko_KR
            → name = \(info.name)
            → encounters (\(info.encounters.count)개):
            \(encs.isEmpty ? "  (없음)" : encs)
            """
        }
    }

    func queryBlizzardMPlusIndex() async {
        await withQuery(action: "Blizzard mythic-keystone/dungeon/index") {
            let token = try await self.fetchBlizzardToken()
            let data = try await self.blizzardClient.fetchMythicKeystoneDungeonIndex(
                locale: "ko_KR", token: token
            )
            return "🟢 /data/wow/mythic-keystone/dungeon/index\n" + Self.prettyJSON(data, limit: 2500)
        }
    }

    func queryBlizzardMPlusDungeon() async {
        await withQuery(action: "Blizzard mythic-keystone/dungeon/{cmMapID}") {
            guard let id = Int(self.cmMapID) else {
                return "❌ CM mapID 숫자 변환 실패"
            }
            let token = try await self.fetchBlizzardToken()
            let data = try await self.blizzardClient.fetchMythicKeystoneDungeon(
                dungeonID: id, locale: "ko_KR", token: token
            )
            return "🟢 /data/wow/mythic-keystone/dungeon/\(id)?locale=ko_KR\n" + Self.prettyJSON(data, limit: 3000)
        }
    }

    // MARK: - Helpers

    private func fetchBlizzardToken() async throws -> String {
        guard !blizzardClientID.isEmpty, !blizzardClientSecret.isEmpty else {
            throw AppError.authenticationFailed
        }
        return try await blizzardClient.fetchAccessToken(
            clientID: blizzardClientID, clientSecret: blizzardClientSecret
        )
    }

    private func withQuery(action: String, _ block: @escaping () async throws -> String) async {
        isBusy = true
        currentAction = action
        defer { isBusy = false; currentAction = "" }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let header = "\n===== \(timestamp) | \(action) =====\n"
        do {
            let body = try await block()
            appendLog(header + body)
        } catch {
            appendLog(header + "❌ ERROR: \(error.localizedDescription)")
            logger.error("\(action) 실패: \(String(describing: error))")
        }
    }

    private func appendLog(_ entry: String) {
        // 최신이 위로 오도록 prepend
        if resultLog.isEmpty {
            resultLog = entry
        } else {
            resultLog = entry + "\n" + resultLog
        }
    }

    private static func prettyJSON(_ data: Data, limit: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return String(str.prefix(limit)) + (str.count > limit ? "\n... (\(str.count - limit) 자 더)" : "")
        }
        // JSON 파싱 실패 시 raw string
        return String(data: data.prefix(limit), encoding: .utf8) ?? "<non-utf8>"
    }
}
