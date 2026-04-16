import Foundation
import os

// Blizzard Battle.net Game Data API 클라이언트.
//
// 목적: spellID → 정식 한국어/영어 이름 해석. WCL masterData 는 로그 녹화 시
// 서버 로캘 기반이라 일관성이 떨어지고 누락이 있을 수 있어, Blizzard 공식
// API 를 ground-truth 로 사용한다.
//
// 인증: OAuth2 Client Credentials Grant
//   POST https://oauth.battle.net/token
//   Authorization: Basic base64(clientID:clientSecret)
//   body: grant_type=client_credentials
//
// Spell API:
//   GET https://kr.api.blizzard.com/data/wow/spell/{id}?namespace=static-kr&locale=ko_KR
//   Authorization: Bearer <token>
//
// Region: 현재는 `kr` 고정. 추후 locale 확장 시 region 파라미터화.
protocol BlizzardGameDataAPIClient {
    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String
    func fetchSpell(spellID: Int, locale: String, token: String) async throws -> BlizzardSpellInfo
    func fetchSpellMedia(spellID: Int, token: String) async throws -> String?
    func fetchJournalEncounter(encounterID: Int, locale: String, token: String) async throws -> (name: String, abilities: [BossAbilityInfo])
    func fetchJournalInstance(instanceID: Int, locale: String, token: String) async throws -> JournalInstanceInfo
    func fetchPlayableSpecialization(specID: Int, token: String) async throws -> SpecAbilityInfo
}

struct BlizzardSpellInfo: Equatable {
    let id: Int
    let name: String
}

final class BlizzardGameDataAPIClientImpl: BlizzardGameDataAPIClient {
    private let session: URLSession
    private let region: String  // "kr", "us", "eu" — 현재는 kr 기본
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "BlizzardAPI")

    init(session: URLSession? = nil, region: String = "kr") {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config)
        }
        self.region = region
    }

    func fetchAccessToken(clientID: String, clientSecret: String) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "oauth.battle.net"
        components.path = "/token"

        guard let url = components.url else {
            throw AppError.networkError("Invalid Blizzard token endpoint")
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

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            logger.error("Blizzard OAuth failed: \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
            throw AppError.authenticationFailed
        }

        struct TokenResponse: Decodable {
            let access_token: String
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
        } catch {
            throw AppError.decodingFailed
        }
    }

    func fetchSpell(spellID: Int, locale: String, token: String) async throws -> BlizzardSpellInfo {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(region).api.blizzard.com"
        components.path = "/data/wow/spell/\(spellID)"
        components.queryItems = [
            URLQueryItem(name: "namespace", value: "static-\(region)"),
            URLQueryItem(name: "locale", value: locale),
        ]

        guard let url = components.url else {
            throw AppError.networkError("Invalid Blizzard spell endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("Invalid response")
        }
        if http.statusCode == 404 {
            throw AppError.networkError("Spell \(spellID) not found in Blizzard API")
        }
        if http.statusCode != 200 {
            throw AppError.networkError("Blizzard API status \(http.statusCode)")
        }

        struct SpellResponse: Decodable {
            let id: Int
            let name: String
        }
        do {
            let decoded = try JSONDecoder().decode(SpellResponse.self, from: data)
            return BlizzardSpellInfo(id: decoded.id, name: decoded.name)
        } catch {
            logger.error("Blizzard spell decode failed for \(spellID, privacy: .public)")
            throw AppError.decodingFailed
        }
    }

    func fetchSpellMedia(spellID: Int, token: String) async throws -> String? {
        let url = try buildURL(path: "/data/wow/media/spell/\(spellID)", queryItems: [
            URLQueryItem(name: "namespace", value: "static-\(region)"),
        ])
        let data = try await performGet(url: url, token: token)

        struct MediaResponse: Decodable {
            let assets: [MediaAsset]?
        }
        struct MediaAsset: Decodable {
            let key: String
            let value: String
        }

        let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
        return decoded.assets?.first(where: { $0.key == "icon" })?.value
    }

    func fetchJournalEncounter(encounterID: Int, locale: String, token: String) async throws -> (name: String, abilities: [BossAbilityInfo]) {
        let url = try buildURL(path: "/data/wow/journal-encounter/\(encounterID)", queryItems: [
            URLQueryItem(name: "namespace", value: "static-\(region)"),
            URLQueryItem(name: "locale", value: locale),
        ])
        let data = try await performGet(url: url, token: token)

        struct EncounterResponse: Decodable {
            let name: String
            let sections: [EncounterSection]?
        }
        struct EncounterSection: Decodable {
            let spellID: SpellRef?
            let title: String?
            let sections: [EncounterSection]?

            enum CodingKeys: String, CodingKey {
                case spellID = "spell"
                case title
                case sections
            }
        }
        struct SpellRef: Decodable {
            let id: Int
            let name: String
        }

        let decoded = try JSONDecoder().decode(EncounterResponse.self, from: data)
        var abilities: [BossAbilityInfo] = []
        func walk(_ sections: [EncounterSection]?) {
            guard let sections else { return }
            for section in sections {
                if let spell = section.spellID {
                    abilities.append(BossAbilityInfo(
                        spellID: spell.id,
                        name: spell.name,
                        description: section.title ?? ""
                    ))
                }
                walk(section.sections)
            }
        }
        walk(decoded.sections)
        return (name: decoded.name, abilities: abilities)
    }

    func fetchJournalInstance(instanceID: Int, locale: String, token: String) async throws -> JournalInstanceInfo {
        let url = try buildURL(path: "/data/wow/journal-instance/\(instanceID)", queryItems: [
            URLQueryItem(name: "namespace", value: "static-\(region)"),
            URLQueryItem(name: "locale", value: locale),
        ])
        let data = try await performGet(url: url, token: token)

        struct InstanceResponse: Decodable {
            let id: Int
            let name: String
            let encounters: [EncounterRef]?
        }
        struct EncounterRef: Decodable {
            let id: Int
            let name: String
        }

        let decoded = try JSONDecoder().decode(InstanceResponse.self, from: data)
        let encounters = (decoded.encounters ?? []).map {
            JournalEncounterSummary(encounterID: $0.id, name: $0.name)
        }
        return JournalInstanceInfo(instanceID: decoded.id, name: decoded.name, encounters: encounters)
    }

    func fetchPlayableSpecialization(specID: Int, token: String) async throws -> SpecAbilityInfo {
        let url = try buildURL(path: "/data/wow/playable-specialization/\(specID)", queryItems: [
            URLQueryItem(name: "namespace", value: "static-\(region)"),
            URLQueryItem(name: "locale", value: "en_US"),
        ])
        let data = try await performGet(url: url, token: token)

        struct SpecResponse: Decodable {
            let id: Int
            let name: String
            let talentTiers: [TalentTier]?

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case talentTiers = "talent_tiers"
            }
        }
        struct TalentTier: Decodable {
            let talents: [TalentEntry]?
        }
        struct TalentEntry: Decodable {
            let spell: SpellRef?
        }
        struct SpellRef: Decodable {
            let id: Int
        }

        let decoded = try JSONDecoder().decode(SpecResponse.self, from: data)
        var spellIDs: [Int] = []
        for tier in decoded.talentTiers ?? [] {
            for talent in tier.talents ?? [] {
                if let spell = talent.spell {
                    spellIDs.append(spell.id)
                }
            }
        }
        return SpecAbilityInfo(specID: decoded.id, specName: decoded.name, spellIDs: spellIDs)
    }

    // MARK: - Helpers

    private func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(region).api.blizzard.com"
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else {
            throw AppError.networkError("Invalid Blizzard API URL: \(path)")
        }
        return url
    }

    private func performGet(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("Invalid response")
        }
        if http.statusCode == 404 {
            throw AppError.networkError("Not found: \(url.path)")
        }
        if http.statusCode != 200 {
            throw AppError.networkError("Blizzard API status \(http.statusCode)")
        }
        return data
    }
}
