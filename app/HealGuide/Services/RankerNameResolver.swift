import Foundation
import os

// MARK: - Protocol

// encounterID / spellID 를 Blizzard Game Data API 로 한국어 이름 해상.
// 자격증명 미설정이면 빈 결과 반환 (에러 안 던짐) → 호출부는 숫자 fallback.
protocol RankerNameResolver {
    func resolveNames(
        encounterIDs: Set<Int>,
        spellIDs:     Set<Int>,
        clientID:     String,
        clientSecret: String
    ) async -> NameResolveResult
}

struct NameResolveResult {
    let encounterNames: [Int: String]
    let spellNames:     [Int: String]

    static let empty = NameResolveResult(encounterNames: [:], spellNames: [:])
}

// MARK: - Implementation

// 세션 내 in-memory 캐시로 동일 ID 중복 호출 방지. actor 로 동시성 보호.
actor RankerNameResolverImpl: RankerNameResolver {
    private let apiClient: any BlizzardGameDataAPIClient
    private var encounterCache: [Int: String] = [:]
    private var spellCache:     [Int: String] = [:]
    private var cachedToken: String?
    private var tokenObtainedAt: Date?
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "NameResolver")

    // Blizzard OAuth 토큰 기본 TTL 은 24시간. 23시간 기준으로 선제 갱신.
    private static let tokenTTLSeconds: TimeInterval = 23 * 3600

    init(apiClient: any BlizzardGameDataAPIClient = BlizzardGameDataAPIClientImpl()) {
        self.apiClient = apiClient
    }

    func resolveNames(
        encounterIDs: Set<Int>,
        spellIDs:     Set<Int>,
        clientID:     String,
        clientSecret: String
    ) async -> NameResolveResult {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            return .empty
        }

        // 토큰 획득 (세션 내 재사용 + TTL 기반 선제 갱신)
        guard let token = await ensureToken(clientID: clientID, clientSecret: clientSecret) else {
            return .empty
        }

        // 캐시 히트 분리
        var encounterResult: [Int: String] = [:]
        var spellResult:     [Int: String] = [:]

        let missingEncounters = encounterIDs.filter {
            if let name = encounterCache[$0] { encounterResult[$0] = name; return false }
            return true
        }
        let missingSpells = spellIDs.filter {
            if let name = spellCache[$0] { spellResult[$0] = name; return false }
            return true
        }

        // encounter / spell 조회는 서로 독립적 → async let 으로 동시 실행
        async let encountersFetch = fetchEncountersParallel(ids: missingEncounters, token: token)
        async let spellsFetch     = fetchSpellsParallel(ids: missingSpells, token: token)
        let (fetchedEncounters, fetchedSpells) = await (encountersFetch, spellsFetch)

        for (id, name) in fetchedEncounters {
            encounterCache[id] = name
            encounterResult[id] = name
        }
        for (id, name) in fetchedSpells {
            spellCache[id] = name
            spellResult[id] = name
        }

        return NameResolveResult(
            encounterNames: encounterResult,
            spellNames:     spellResult
        )
    }

    // MARK: - Token management

    private func ensureToken(clientID: String, clientSecret: String) async -> String? {
        if let cached = cachedToken, let obtainedAt = tokenObtainedAt,
           Date().timeIntervalSince(obtainedAt) < Self.tokenTTLSeconds {
            return cached
        }
        // 만료되었거나 미획득 상태 → 재발급
        cachedToken = nil
        tokenObtainedAt = nil
        do {
            let fresh = try await apiClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
            cachedToken = fresh
            tokenObtainedAt = Date()
            return fresh
        } catch {
            logger.warning("Blizzard 토큰 발급 실패 — 이름 조회 스킵: \(error)")
            return nil
        }
    }

    // MARK: - Private parallel fetch

    private func fetchEncountersParallel(ids: Set<Int>, token: String) async -> [Int: String] {
        guard !ids.isEmpty else { return [:] }
        return await withTaskGroup(of: (Int, String)?.self) { group in
            for id in ids {
                group.addTask { [apiClient] in
                    do {
                        let result = try await apiClient.fetchJournalEncounter(
                            encounterID: id, locale: "ko_KR", token: token
                        )
                        return (id, result.name)
                    } catch {
                        return nil
                    }
                }
            }
            var acc: [Int: String] = [:]
            for await pair in group {
                if let (id, name) = pair { acc[id] = name }
            }
            return acc
        }
    }

    private func fetchSpellsParallel(ids: Set<Int>, token: String) async -> [Int: String] {
        guard !ids.isEmpty else { return [:] }
        return await withTaskGroup(of: (Int, String)?.self) { group in
            for id in ids {
                group.addTask { [apiClient] in
                    do {
                        let info = try await apiClient.fetchSpell(
                            spellID: id, locale: "ko_KR", token: token
                        )
                        return (id, info.name)
                    } catch {
                        return nil
                    }
                }
            }
            var acc: [Int: String] = [:]
            for await pair in group {
                if let (id, name) = pair { acc[id] = name }
            }
            return acc
        }
    }
}

// MARK: - Mock

final class MockRankerNameResolver: RankerNameResolver {
    var stubbedEncounters: [Int: String] = [:]
    var stubbedSpells:     [Int: String] = [:]

    func resolveNames(
        encounterIDs: Set<Int>,
        spellIDs:     Set<Int>,
        clientID:     String,
        clientSecret: String
    ) async -> NameResolveResult {
        NameResolveResult(
            encounterNames: stubbedEncounters.filter { encounterIDs.contains($0.key) },
            spellNames:     stubbedSpells.filter     { spellIDs.contains($0.key) }
        )
    }
}
