import Foundation
import os

enum HostilityType: String {
    case friendly = "Friendlies"
    case hostile = "Enemies"
}

protocol WarcraftLogsAPIClient {
    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String
    func fetchFight(reportCode: String, fightID: Int, token: String) async throws -> FightMeta
    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> [BossWindow]
    func fetchCasts(
        reportCode: String,
        fightID: Int,
        sourceID: Int?,
        hostilityType: HostilityType,
        startTime: Int64,
        endTime: Int64,
        token: String
    ) async throws -> [CastEvent]
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

    func fetchFight(reportCode: String, fightID: Int, token: String) async throws -> FightMeta {
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

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<FightQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            guard let fight = decoded.data?.reportData?.report?.fights.first else {
                throw AppError.fightNotFound
            }
            return FightMeta(
                id: fight.id,
                encounterID: fight.encounterID,
                name: fight.name,
                startTime: Int64(fight.startTime.rounded()),
                endTime: Int64(fight.endTime.rounded()),
                kill: fight.kill ?? false
            )
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("Fight decoding failed: \(error)")
            throw AppError.decodingFailed
        }
    }

    func fetchEncounters(reportCode: String, fightID: Int, token: String) async throws -> [BossWindow] {
        var allEvents: [EncounterEventPayload] = []
        var currentStartTime: Double? = nil

        for _ in 0..<Self.maxPaginationPages {
            let (pageEvents, nextTimestamp) = try await fetchEncountersPage(
                reportCode: reportCode,
                fightID: fightID,
                startTime: currentStartTime,
                token: token
            )
            allEvents.append(contentsOf: pageEvents)
            guard let next = nextTimestamp else { break }
            currentStartTime = next
        }

        return pairEncounterEvents(allEvents)
    }

    private func fetchEncountersPage(
        reportCode: String,
        fightID: Int,
        startTime: Double?,
        token: String
    ) async throws -> ([EncounterEventPayload], Double?) {
        let url = try graphQLURL()

        let query = """
        query($code: String!, $fightIDs: [Int]!, $startTime: Float) {
          reportData {
            report(code: $code) {
              events(fightIDs: $fightIDs, dataType: Encounters, startTime: $startTime) {
                data
                nextPageTimestamp
              }
            }
          }
        }
        """

        var variables: [String: GraphQLVariable] = [
            "code": .string(reportCode),
            "fightIDs": .intArray([fightID])
        ]
        if let startTime {
            variables["startTime"] = .double(startTime)
        }

        let body = GraphQLRequest(query: query, variables: variables)
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<EncountersQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            let events = decoded.data?.reportData?.report?.events
            return (events?.data ?? [], events?.nextPageTimestamp)
        } catch let appError as AppError {
            throw appError
        } catch {
            logger.error("Encounters page decoding failed: \(error)")
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

    private func pairEncounterEvents(_ events: [EncounterEventPayload]) -> [BossWindow] {
        var pendingStarts: [Int: (name: String, startTime: Int64)] = [:]
        var windows: [BossWindow] = []

        for event in events {
            guard let encounterID = event.encounterID else { continue }
            if event.type == "encounterstart" {
                guard let name = event.name else { continue }
                pendingStarts[encounterID] = (name, event.timestamp)
            } else if event.type == "encounterend" {
                guard let pending = pendingStarts[encounterID] else { continue }
                windows.append(BossWindow(
                    encounterID: encounterID,
                    name: pending.name,
                    startTime: pending.startTime,
                    endTime: event.timestamp
                ))
                pendingStarts.removeValue(forKey: encounterID)
            }
        }

        return windows
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

// MARK: - fetchFight response types

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
}

// MARK: - fetchEncounters response types

private struct EncountersQueryData: Decodable {
    let reportData: EncountersReportData?
}

private struct EncountersReportData: Decodable {
    let report: EncountersReport?
}

private struct EncountersReport: Decodable {
    let events: EncounterEventsPage?
}

private struct EncounterEventsPage: Decodable {
    let data: [EncounterEventPayload]
    let nextPageTimestamp: Double?
}

private struct EncounterEventPayload: Decodable {
    let type: String?
    let timestamp: Int64
    let encounterID: Int?
    let name: String?
}

// MARK: - fetchCasts response types

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
