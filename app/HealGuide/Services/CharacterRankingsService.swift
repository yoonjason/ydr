import Foundation
import os

// MARK: - Protocol

protocol CharacterRankingsService {
    /// WarcraftLogs characterRankings 쿼리 실행 → 상위 N 파스 반환 (탤런트 포함)
    func fetchCharacterRankings(
        encounterId:  Int,
        className:    String,
        specName:     String,
        difficulty:   Int?,
        serverRegion: String,
        limit:        Int,
        token:        String
    ) async throws -> [RankerParse]
}

// MARK: - Implementation

final class CharacterRankingsServiceImpl: CharacterRankingsService {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "CharacterRankings")

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest  = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
    }

    func fetchCharacterRankings(
        encounterId:  Int,
        className:    String,
        specName:     String,
        difficulty:   Int?,
        serverRegion: String,
        limit:        Int,
        token:        String
    ) async throws -> [RankerParse] {
        let url = try graphQLURL()

        // characterRankings 는 JSON scalar 반환이므로 raw JSON 필드로 수신 후 재파싱
        let query = """
        query(
          $encounterId: Int!, $className: String!, $specName: String!,
          $serverRegion: String, $difficulty: Int
        ) {
          worldData {
            encounter(id: $encounterId) {
              characterRankings(
                className: $className
                specName: $specName
                serverRegion: $serverRegion
                difficulty: $difficulty
              )
            }
          }
        }
        """

        var variables: [String: CRGraphQLVariable] = [
            "encounterId":  .int(encounterId),
            "className":    .string(className),
            "specName":     .string(specName),
            "serverRegion": .string(serverRegion),
        ]
        if let difficulty {
            variables["difficulty"] = .int(difficulty)
        }

        let body = CRGraphQLRequest(query: query, variables: variables)
        let request = try buildRequest(url: url, body: body, token: token)
        let (data, response) = try await perform(request)
        try validate(response: response)

        do {
            let decoded = try JSONDecoder().decode(CRGraphQLResponse<WorldDataWrapper>.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw AppError.networkError(errors[0].message)
            }
            let scalar = decoded.data?.worldData?.encounter?.characterRankings
            let allRankings = scalar?.rankings ?? []
            return Array(allRankings.prefix(limit)).map { ranking in
                let talentIDs = Set((ranking.talents ?? []).map(\.id))
                return RankerParse(
                    id: "\(ranking.report.code)-\(ranking.report.fightID)",
                    reportCode: ranking.report.code,
                    fightID: ranking.report.fightID,
                    talentNodeIDs: talentIDs,
                    characterName: ranking.name
                )
            }
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("characterRankings 디코딩 실패: \(error)")
            throw AppError.decodingFailed
        }
    }

    // MARK: - HTTP Helpers

    private func graphQLURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host   = "www.warcraftlogs.com"
        components.path   = "/api/v2/client"
        guard let url = components.url else {
            throw AppError.networkError("Invalid GraphQL endpoint URL")
        }
        return url
    }

    private func buildRequest(url: URL, body: CRGraphQLRequest, token: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            logger.error("GraphQL 요청 인코딩 실패: \(error)")
            throw AppError.networkError("Request encoding failed")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.networkError("Invalid response type")
            }
            return (data, http)
        } catch let error as AppError {
            throw error
        } catch {
            logger.error("네트워크 요청 실패: \(error)")
            throw AppError.networkError(error.localizedDescription)
        }
    }

    private func validate(response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: break
        case 401:       throw AppError.authenticationFailed
        default:        throw AppError.networkError("HTTP \(response.statusCode)")
        }
    }
}

// MARK: - Private GraphQL Types

private struct CRGraphQLRequest: Encodable {
    let query:     String
    let variables: [String: CRGraphQLVariable]
}

private enum CRGraphQLVariable: Encodable {
    case string(String)
    case int(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value):    try container.encode(value)
        }
    }
}

private struct CRGraphQLResponse<T: Decodable>: Decodable {
    let data:   T?
    let errors: [CRGraphQLError]?
}

private struct CRGraphQLError: Decodable {
    let message: String
}

private struct WorldDataWrapper: Decodable {
    let worldData: WorldData?
    struct WorldData: Decodable {
        let encounter: EncounterWrapper?
        struct EncounterWrapper: Decodable {
            let characterRankings: CharacterRankingsScalar?
        }
    }
}

// characterRankings 는 JSON scalar → 별도 Decodable 로 재파싱
private struct CharacterRankingsScalar: Decodable {
    let rankings: [CharacterRanking]?

    struct CharacterRanking: Decodable {
        let name:    String
        let report:  ReportRef
        let talents: [TalentEntry]?

        struct ReportRef: Decodable {
            let code:    String
            let fightID: Int
        }

        struct TalentEntry: Decodable {
            let id:   Int
            let rank: Int?
        }
    }
}

// MARK: - Mock

final class MockCharacterRankingsService: CharacterRankingsService {
    var result: Result<[RankerParse], AppError> = .success([])

    func fetchCharacterRankings(
        encounterId:  Int,
        className:    String,
        specName:     String,
        difficulty:   Int?,
        serverRegion: String,
        limit:        Int,
        token:        String
    ) async throws -> [RankerParse] {
        try result.get()
    }
}
