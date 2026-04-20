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
    private var cachedToken: String?  // 세션 내 토큰 재사용
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "NameResolver")

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

        // 토큰 획득 (세션 내 재사용)
        let token: String
        if let cached = cachedToken {
            token = cached
        } else {
            do {
                token = try await apiClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
                cachedToken = token
            } catch {
                logger.warning("Blizzard 토큰 발급 실패 — 이름 조회 스킵: \(error)")
                return .empty
            }
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

        // 미스 항목 병렬 조회 (개별 실패는 nil 로 스킵)
        let fetchedEncounters = await fetchEncountersParallel(ids: missingEncounters, token: token)
        let fetchedSpells     = await fetchSpellsParallel(ids: missingSpells, token: token)

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
