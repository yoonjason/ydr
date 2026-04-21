import Foundation
import os

enum HostilityType: String {
    case friendly = "Friendlies"
    case hostile = "Enemies"
}

protocol WarcraftLogsAPIClient: Sendable {
    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String
    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> (dungeonName: String, windows: [BossWindow])
    func fetchPlayerDetails(reportCode: String, fightID: Int, token: String) async throws -> [HealerCandidate]
    func fetchCasts(
        reportCode: String,
        fightID: Int,
        sourceID: Int?,
        hostilityType: HostilityType,
        startTime: Int64,
        endTime: Int64,
        token: String
    ) async throws -> [CastEvent]
    func fetchMasterData(reportCode: String, token: String) async throws -> [MasterDataAbility]
    // ReportFight.talentImportCode(actorID:) — WoW 인게임 탤런트 창에 붙여넣기 가능한 export 문자열.
    // null 반환: non-player actor 또는 WCL 이 해당 파스의 탤런트를 기록 못 한 경우.
    func fetchTalentImportCode(reportCode: String, fightID: Int, actorID: Int, token: String) async throws -> String?
    // worldData.encounter(id:).name — WCL 자체 encID 공간 기준 보스/인카운터 이름.
    // M+ 던전의 경우 ID 가 WCL 자체 스킴이라 Blizzard journal-encounter 와 다름.
    func fetchEncounterName(encounterID: Int, token: String) async throws -> String?
}

final class WarcraftLogsAPIClientImpl: WarcraftLogsAPIClient {
    private static let maxPaginationPages = 100

    private let session: URLSession
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "WarcraftLogsAPI")

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
    }

    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.warcraftlogs.com"
        components.path = "/oauth/token"

        guard let url = components.url else {
            throw AppError.networkError("Invalid token endpoint URL")
        }

        let credentials = "\(clientID):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw AppError.authenticationFailed
        }
        let base64 = credentialsData.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            return decoded.accessToken
        } catch {
            logger.error("Token decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> (dungeonName: String, windows: [BossWindow]) {
        let url = try graphQLURL()

        let query = """
        query($code: String!, $fightIDs: [Int]!) {
          reportData {
            report(code: $code) {
              fights(fightIDs: $fightIDs) {
                id
                encounterID
                name
                startTime
                endTime
                kill
                dungeonPulls {
                  id
                  encounterID
                  name
                  startTime
                  endTime
                  kill
                }
              }
            }
          }
        }
        """

        let body = GraphQLRequest(
            query: query,
            variables: ["code": .string(reportCode), "fightIDs": .intArray([fightID])]
        )

        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        let fight: FightPayload
        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<FightQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            guard let found = decoded.data?.reportData?.report?.fights.first else {
                throw AppError.fightNotFound
            }
            fight = found
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("Encounters decoding failed: \(error)")
            throw AppError.decodingFailed
        }

        // M+ 던전 fight도 자체 encounterID > 0 을 가지므로 encounterID 만으로는 레이드/M+ 구분 불가.
        // dungeonPulls 가 비어있지 않으면 M+ 던전 → 하위 보스 펄에서 추출.
        // 비어있으면 단일 보스 fight (레이드) → 자기 자신을 윈도우로 반환.
        let pulls = fight.dungeonPulls ?? []
        let bossPulls = pulls.filter { $0.encounterID > 0 }

        if !bossPulls.isEmpty {
            let windows = bossPulls.map { pull in
                BossWindow(
                    encounterID: pull.encounterID,
                    name: pull.name,
                    startTime: Int64(pull.startTime.rounded()),
                    endTime: Int64(pull.endTime.rounded())
                )
            }
            return (dungeonName: fight.name, windows: windows)
        }

        if fight.encounterID > 0 {
            return (
                dungeonName: fight.name,
                windows: [BossWindow(
                    encounterID: fight.encounterID,
                    name: fight.name,
                    startTime: Int64(fight.startTime.rounded()),
                    endTime: Int64(fight.endTime.rounded())
                )]
            )
        }

        throw AppError.noBossEncounters
    }

    func fetchPlayerDetails(reportCode: String, fightID: Int, token: String) async throws -> [HealerCandidate] {
        let url = try graphQLURL()

        let query = """
        query($code: String!, $fightIDs: [Int]!) {
          reportData {
            report(code: $code) {
              playerDetails(fightIDs: $fightIDs)
            }
          }
        }
        """

        let body = GraphQLRequest(
            query: query,
            variables: ["code": .string(reportCode), "fightIDs": .intArray([fightID])]
        )
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<PlayerDetailsQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            let healers = decoded.data?.reportData?.report?.playerDetails?.data?.playerDetails?.healers ?? []
            let mapped = healers.map { dto -> HealerCandidate in
                let specName = dto.specs?.first?.spec ?? ""
                return HealerCandidate(
                    id: dto.id,
                    name: dto.name,
                    className: dto.type,
                    specName: specName,
                    server: dto.server
                )
            }
            return mapped
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("PlayerDetails decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    func fetchCasts(
        reportCode: String,
        fightID: Int,
        sourceID: Int?,
        hostilityType: HostilityType,
        startTime: Int64,
        endTime: Int64,
        token: String
    ) async throws -> [CastEvent] {
        var allCasts: [CastEvent] = []
        var currentStartTime: Double = Double(startTime)
        let endTimeDouble = Double(endTime)

        for _ in 0..<Self.maxPaginationPages {
            let (pageCasts, nextTimestamp) = try await fetchCastsPage(
                reportCode: reportCode,
                fightID: fightID,
                sourceID: sourceID,
                hostilityType: hostilityType,
                startTime: currentStartTime,
                endTime: endTimeDouble,
                token: token
            )
            allCasts.append(contentsOf: pageCasts)
            guard let next = nextTimestamp, next <= endTimeDouble else { break }
            currentStartTime = next
        }

        return allCasts
    }

    private func fetchCastsPage(
        reportCode: String,
        fightID: Int,
        sourceID: Int?,
        hostilityType: HostilityType,
        startTime: Double,
        endTime: Double,
        token: String
    ) async throws -> ([CastEvent], Double?) {
        let url = try graphQLURL()

        let query = """
        query($code: String!, $fightIDs: [Int]!, $sourceID: Int, $hostilityType: HostilityType!, $startTime: Float!, $endTime: Float!) {
          reportData {
            report(code: $code) {
              events(
                fightIDs: $fightIDs
                sourceID: $sourceID
                hostilityType: $hostilityType
                dataType: Casts
                startTime: $startTime
                endTime: $endTime
              ) {
                data
                nextPageTimestamp
              }
            }
          }
        }
        """

        var variables: [String: GraphQLVariable] = [
            "code": .string(reportCode),
            "fightIDs": .intArray([fightID]),
            "hostilityType": .string(hostilityType.rawValue),
            "startTime": .double(startTime),
            "endTime": .double(endTime)
        ]
        if let sourceID {
            variables["sourceID"] = .int(sourceID)
        }

        let body = GraphQLRequest(query: query, variables: variables)
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<CastsQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            let events = decoded.data?.reportData?.report?.events
            let payloads = events?.data ?? []
            let nextTimestamp = events?.nextPageTimestamp

            let castEvents = payloads.compactMap { payload -> CastEvent? in
                guard payload.type == "cast",
                      let spellID = payload.abilityGameID else { return nil }
                return CastEvent(
                    timestamp: payload.timestamp,
                    spellID: spellID,
                    sourceID: payload.sourceID ?? 0
                )
            }
            return (castEvents, nextTimestamp)
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("Casts decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    func fetchMasterData(reportCode: String, token: String) async throws -> [MasterDataAbility] {
        let url = try graphQLURL()

        let query = """
        query($code: String!) {
          reportData {
            report(code: $code) {
              masterData {
                abilities {
                  gameID
                  name
                  icon
                }
              }
            }
          }
        }
        """

        let body = GraphQLRequest(
            query: query,
            variables: ["code": .string(reportCode)]
        )
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<MasterDataQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            let abilities = decoded.data?.reportData?.report?.masterData?.abilities ?? []
            return abilities.map { MasterDataAbility(gameID: $0.gameID, name: $0.name, icon: $0.icon) }
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("MasterData decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    func fetchEncounterName(encounterID: Int, token: String) async throws -> String? {
        let url = try graphQLURL()
        let query = """
        query($id: Int!) {
          worldData {
            encounter(id: $id) {
              name
            }
          }
        }
        """
        let body = GraphQLRequest(query: query, variables: ["id": .int(encounterID)])
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<EncounterNameQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            return decoded.data?.worldData?.encounter?.name
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("EncounterName decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    func fetchTalentImportCode(reportCode: String, fightID: Int, actorID: Int, token: String) async throws -> String? {
        let url = try graphQLURL()

        // reportData.report(code:).fights(fightIDs:)[0].talentImportCode(actorID:) → String?
        let query = """
        query($code: String!, $fightIDs: [Int]!, $actorID: Int!) {
          reportData {
            report(code: $code) {
              fights(fightIDs: $fightIDs) {
                talentImportCode(actorID: $actorID)
              }
            }
          }
        }
        """

        let body = GraphQLRequest(
            query: query,
            variables: [
                "code":     .string(reportCode),
                "fightIDs": .intArray([fightID]),
                "actorID":  .int(actorID)
            ]
        )
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<TalentImportQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            return decoded.data?.reportData?.report?.fights?.first?.talentImportCode
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("TalentImportCode decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    private func graphQLURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.warcraftlogs.com"
        components.path = "/api/v2/client"
        guard let url = components.url else {
            throw AppError.networkError("Invalid GraphQL endpoint URL")
        }
        return url
    }

    private func buildRequest(url: URL, body: GraphQLRequest, token: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            logger.error("GraphQL request encoding failed: \(error)")
            throw AppError.networkError("Request encoding failed")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.networkError("Invalid response type")
            }
            return (data, httpResponse)
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("Network request failed: \(error)")
            throw AppError.networkError(error.localizedDescription)
        }
    }

    private func validate(response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            break
        case 401:
            throw AppError.authenticationFailed
        default:
            throw AppError.networkError("HTTP \(response.statusCode)")
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: GraphQLVariable]
}

private enum GraphQLVariable: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case intArray([Int])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .intArray(let value):
            try container.encode(value)
        }
    }
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct FightQueryData: Decodable {
    let reportData: FightReportData?
}

private struct FightReportData: Decodable {
    let report: FightReport?
}

private struct FightReport: Decodable {
    let fights: [FightPayload]
}

private struct FightPayload: Decodable {
    let id: Int
    let encounterID: Int
    let name: String
    let startTime: Double
    let endTime: Double
    let kill: Bool?
    let dungeonPulls: [DungeonPullPayload]?
}

private struct DungeonPullPayload: Decodable {
    let id: Int
    let encounterID: Int
    let name: String
    let startTime: Double
    let endTime: Double
    let kill: Bool?
}

private struct CastsQueryData: Decodable {
    let reportData: CastsReportData?
}

private struct CastsReportData: Decodable {
    let report: CastsReport?
}

private struct CastsReport: Decodable {
    let events: EventsPage?
}

private struct EventsPage: Decodable {
    let data: [RawEventPayload]
    let nextPageTimestamp: Double?
}

private struct RawEventPayload: Decodable {
    let type: String?
    let timestamp: Int64
    let sourceID: Int?
    let abilityGameID: Int?
}

// MARK: - masterData

private struct MasterDataQueryData: Decodable {
    let reportData: MasterDataReportData?
}

private struct MasterDataReportData: Decodable {
    let report: MasterDataReport?
}

private struct MasterDataReport: Decodable {
    let masterData: MasterDataPayload?
}

private struct MasterDataPayload: Decodable {
    let abilities: [MasterDataAbilityDTO]
}

private struct MasterDataAbilityDTO: Decodable {
    let gameID: Int
    let name: String
    let icon: String?
}

// MARK: - encounterName

private struct EncounterNameQueryData: Decodable {
    let worldData: WorldDataEnc?
    struct WorldDataEnc: Decodable {
        let encounter: EncounterWithName?
        struct EncounterWithName: Decodable {
            let name: String?
        }
    }
}

// MARK: - talentImportCode

private struct TalentImportQueryData: Decodable {
    let reportData: TalentImportReportData?
}

private struct TalentImportReportData: Decodable {
    let report: TalentImportReport?
}

private struct TalentImportReport: Decodable {
    let fights: [TalentImportFight]?
}

private struct TalentImportFight: Decodable {
    let talentImportCode: String?
}

// MARK: - playerDetails

private struct PlayerDetailsQueryData: Decodable {
    let reportData: PlayerDetailsReportData?
}

private struct PlayerDetailsReportData: Decodable {
    let report: PlayerDetailsReport?
}

private struct PlayerDetailsReport: Decodable {
    let playerDetails: PlayerDetailsWrapper?
}

// WCL 의 playerDetails 는 JSON 스칼라지만 내부에 { data: { playerDetails: {...} } } 가 한번 더 감싸여 반환된다.
private struct PlayerDetailsWrapper: Decodable {
    let data: PlayerDetailsInnerWrapper?
}

private struct PlayerDetailsInnerWrapper: Decodable {
    let playerDetails: PlayerDetailsRoles?
}

private struct PlayerDetailsRoles: Decodable {
    let healers: [PlayerActorDTO]?
    let tanks: [PlayerActorDTO]?
    let dps: [PlayerActorDTO]?
}

private struct PlayerActorDTO: Decodable {
    let id: Int
    let name: String
    let type: String  // class name (e.g. "Priest")
    let server: String?
    let specs: [PlayerSpecDTO]?
}

private struct PlayerSpecDTO: Decodable {
    let spec: String  // e.g. "Discipline"
    let role: String? // "healer" / "tank" / "dps"
}
