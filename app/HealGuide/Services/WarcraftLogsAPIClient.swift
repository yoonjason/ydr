import Foundation
import os

protocol WarcraftLogsAPIClient {
    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String
    func fetchFight(reportCode: String, fightID: Int, token: String) async throws -> FightMeta
}

final class WarcraftLogsAPIClientImpl: WarcraftLogsAPIClient {
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

    // TODO(T4+): 토큰 만료 전 재사용 캐싱 — 현재는 매 호출마다 재발급
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
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.warcraftlogs.com"
        components.path = "/api/v2/client"

        guard let url = components.url else {
            throw AppError.networkError("Invalid GraphQL endpoint URL")
        }

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

        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(GraphQLResponse<FightQueryData>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            guard let report = decoded.data?.reportData?.report else {
                throw AppError.fightNotFound
            }
            guard let fight = report.fights.first else {
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
    case intArray([Int])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
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
    let reportData: ReportData?
}

private struct ReportData: Decodable {
    let report: Report?
}

private struct Report: Decodable {
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
