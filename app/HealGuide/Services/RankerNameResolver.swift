import Foundation
import os

// MARK: - Protocol

// encounterID → WCL 자체 name, spellID → Blizzard 공식 이름 으로 해상.
//
// 배경: 초기 구현은 encounter 도 Blizzard journal-encounter 로 조회했지만,
// WCL M+ 던전의 encounterID 는 WCL 자체 ID 체계라 Blizzard journal-encounter
// ID 공간과 불일치. 결과적으로 엉뚱한 레이드 보스 이름이 반환되는 버그 발생
// (2026-04-21 handoff 참조). 디버그 탭 실험으로 WCL worldData.encounter(id:).name
// 경로만 정확히 동작 확인 → 해당 경로로 전환.
//
// spellID 는 Blizzard 공식 spellID 로 WCL/WoW/Blizzard API 모두 공통이라 그대로
// Blizzard API 사용 (한국어 이름 품질 우수).
protocol RankerNameResolver {
    func resolveNames(
        encounterIDs: Set<Int>,
        spellIDs:     Set<Int>,
        wclClientID:     String,
        wclClientSecret: String,
        blizzardClientID:     String,
        blizzardClientSecret: String
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
    private let wclClient:      any WarcraftLogsAPIClient
    private let blizzardClient: any BlizzardGameDataAPIClient

    private var encounterCache: [Int: String] = [:]
    private var spellCache:     [Int: String] = [:]

    // 토큰별 분리 캐시 (WCL / Blizzard 각자 OAuth 토큰 TTL 관리)
    private var cachedWCLToken:      String?
    private var wclTokenObtainedAt:  Date?
    private var cachedBlizzardToken:     String?
    private var blizzardTokenObtainedAt: Date?

    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "NameResolver")

    // OAuth 토큰 기본 TTL 은 보통 24시간. 23시간 기준으로 선제 갱신.
    private static let tokenTTLSeconds: TimeInterval = 23 * 3600

    init(
        wclClient:      any WarcraftLogsAPIClient    = WarcraftLogsAPIClientImpl(),
        blizzardClient: any BlizzardGameDataAPIClient = BlizzardGameDataAPIClientImpl()
    ) {
        self.wclClient = wclClient
        self.blizzardClient = blizzardClient
    }

    func resolveNames(
        encounterIDs: Set<Int>,
        spellIDs:     Set<Int>,
        wclClientID:     String,
        wclClientSecret: String,
        blizzardClientID:     String,
        blizzardClientSecret: String
    ) async -> NameResolveResult {
        // encounter 와 spell 은 서로 다른 API + 자격증명이라 독립 처리.
        // 한쪽만 자격증명이 있어도 부분 결과 반환 (graceful degradation).

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

        async let fetchedEncounters = resolveEncountersIfPossible(
            ids: missingEncounters,
            clientID: wclClientID,
            clientSecret: wclClientSecret
        )
        async let fetchedSpells = resolveSpellsIfPossible(
            ids: missingSpells,
            clientID: blizzardClientID,
            clientSecret: blizzardClientSecret
        )
        let (encMap, spellMap) = await (fetchedEncounters, fetchedSpells)

        for (id, name) in encMap {
            encounterCache[id] = name
            encounterResult[id] = name
        }
        for (id, name) in spellMap {
            spellCache[id] = name
            spellResult[id] = name
        }

        return NameResolveResult(
            encounterNames: encounterResult,
            spellNames:     spellResult
        )
    }

    // MARK: - Encounter (WCL)

    private func resolveEncountersIfPossible(
        ids: Set<Int>, clientID: String, clientSecret: String
    ) async -> [Int: String] {
        guard !ids.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty else { return [:] }
        guard let token = await ensureWCLToken(clientID: clientID, clientSecret: clientSecret) else {
            return [:]
        }
        return await fetchEncounterNamesParallel(ids: ids, token: token)
    }

    private func fetchEncounterNamesParallel(ids: Set<Int>, token: String) async -> [Int: String] {
        return await withTaskGroup(of: (Int, String)?.self) { group in
            for id in ids {
                group.addTask { [wclClient] in
                    do {
                        // WCL 이 알 수 없는 ID 에 대해 "" 를 반환할 수 있어 명시적 비어있음 가드.
                        // 빈 문자열을 캐시에 넣으면 UI 에서 공란으로 표시되어 오해 유발.
                        if let name = try await wclClient.fetchEncounterName(encounterID: id, token: token),
                           !name.isEmpty {
                            return (id, name)
                        }
                        return nil
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

    // MARK: - Spell (Blizzard)

    private func resolveSpellsIfPossible(
        ids: Set<Int>, clientID: String, clientSecret: String
    ) async -> [Int: String] {
        guard !ids.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty else { return [:] }
        guard let token = await ensureBlizzardToken(clientID: clientID, clientSecret: clientSecret) else {
            return [:]
        }
        return await fetchSpellsParallel(ids: ids, token: token)
    }

    private func fetchSpellsParallel(ids: Set<Int>, token: String) async -> [Int: String] {
        return await withTaskGroup(of: (Int, String)?.self) { group in
            for id in ids {
                group.addTask { [blizzardClient] in
                    do {
                        let info = try await blizzardClient.fetchSpell(
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

    // MARK: - Token management

    private func ensureWCLToken(clientID: String, clientSecret: String) async -> String? {
        if let cached = cachedWCLToken, let obtainedAt = wclTokenObtainedAt,
           Date().timeIntervalSince(obtainedAt) < Self.tokenTTLSeconds {
            return cached
        }
        cachedWCLToken = nil
        wclTokenObtainedAt = nil
        do {
            let fresh = try await wclClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
            cachedWCLToken = fresh
            wclTokenObtainedAt = Date()
            return fresh
        } catch {
            logger.warning("WCL 토큰 발급 실패 — 이름 조회 스킵: \(error)")
            return nil
        }
    }

    private func ensureBlizzardToken(clientID: String, clientSecret: String) async -> String? {
        if let cached = cachedBlizzardToken, let obtainedAt = blizzardTokenObtainedAt,
           Date().timeIntervalSince(obtainedAt) < Self.tokenTTLSeconds {
            return cached
        }
        cachedBlizzardToken = nil
        blizzardTokenObtainedAt = nil
        do {
            let fresh = try await blizzardClient.fetchAccessToken(clientID: clientID, clientSecret: clientSecret)
            cachedBlizzardToken = fresh
            blizzardTokenObtainedAt = Date()
            return fresh
        } catch {
            logger.warning("Blizzard 토큰 발급 실패 — 스킬 이름 조회 스킵: \(error)")
            return nil
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
        wclClientID:     String,
        wclClientSecret: String,
        blizzardClientID:     String,
        blizzardClientSecret: String
    ) async -> NameResolveResult {
        NameResolveResult(
            encounterNames: stubbedEncounters.filter { encounterIDs.contains($0.key) },
            spellNames:     stubbedSpells.filter     { spellIDs.contains($0.key) }
        )
    }
}
