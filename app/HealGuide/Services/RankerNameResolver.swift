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

    // 영문 per-pull 보스명을 한국어로 치환.
    // dungeonKoreanName: DungeonInfo.name 의 '던전명 (English)' 형식에서 한국어 부분
    //   (예: '윈드러너 첨탑 (Windrunner Spire)' → '윈드러너 첨탑')
    // englishNames: WCL dungeonPulls.name 에서 수집한 [wclEncID: 영문 보스명]
    // 반환: [wclEncID: 한국어 보스명] — 매칭 실패 시 해당 encID 는 빠짐 (호출부에서 영문 fallback)
    func translateEncountersToKorean(
        dungeonKoreanName: String,
        englishNames:      [Int: String],
        blizzardClientID:     String,
        blizzardClientSecret: String
    ) async -> [Int: String]
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
    // 한국어 던전명 → Blizzard journal-instance ID. journal-instance/index 스캔 1회 결과.
    private var dungeonInstanceIDCache: [String: Int] = [:]
    // instance ID → 영문→한국어 보스명 맵. 던전당 1회 페치.
    private var instanceEnToKrCache: [Int: [String: String]] = [:]
    // journal-instance/index 전체 (ko_KR) 를 1회만 페치.
    private var journalIndexKR: [JournalInstanceSummary]?

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

    // MARK: - Encounter KR translation (Blizzard journal-instance 기반)

    func translateEncountersToKorean(
        dungeonKoreanName: String,
        englishNames:      [Int: String],
        blizzardClientID:     String,
        blizzardClientSecret: String
    ) async -> [Int: String] {
        print("[HG-NR-DEBUG] translateEncountersToKorean 진입")
        print("[HG-NR-DEBUG]   dungeonKoreanName = '\(dungeonKoreanName)'")
        print("[HG-NR-DEBUG]   englishNames 수 = \(englishNames.count)")
        print("[HG-NR-DEBUG]   englishNames 내용 = \(englishNames)")

        guard !englishNames.isEmpty,
              !blizzardClientID.isEmpty, !blizzardClientSecret.isEmpty else {
            print("[HG-NR-DEBUG] ❌ guard 실패 — 번역 스킵")
            return [:]
        }
        guard let token = await ensureBlizzardToken(
            clientID: blizzardClientID, clientSecret: blizzardClientSecret
        ) else {
            print("[HG-NR-DEBUG] ❌ Blizzard 토큰 발급 실패")
            return [:]
        }
        print("[HG-NR-DEBUG] ✅ Blizzard 토큰 발급 성공")

        // 1. 던전 이름 매칭되는 모든 instance 후보 수집.
        // Blizzard 가 같은 한국어 이름으로 여러 instance 를 보유할 수 있음 (예: BC 리메이크 이슈).
        let candidateIDs = await findInstanceIDs(dungeonKoreanName: dungeonKoreanName, token: token)
        guard !candidateIDs.isEmpty else {
            print("[HG-NR-DEBUG] ❌ journal-instance/index 에서 '\(dungeonKoreanName)' 미발견")
            logger.warning("journal-instance/index 에서 '\(dungeonKoreanName)' 미발견 — 영문 유지")
            return [:]
        }
        print("[HG-NR-DEBUG] '\(dungeonKoreanName)' 매칭 후보 \(candidateIDs.count)개: \(candidateIDs)")

        // 2. 후보별로 EN→KR 맵 페치 후, WCL 영문명과 최대 겹침 instance 선택.
        let requestedEnglishSet = Set(englishNames.values)
        var bestInstanceID: Int?
        var bestEnToKr: [String: String] = [:]
        var bestOverlap = 0

        for candidateID in candidateIDs {
            let enToKr: [String: String]
            if let cached = instanceEnToKrCache[candidateID] {
                enToKr = cached
            } else {
                enToKr = await fetchEnToKrMap(instanceID: candidateID, token: token)
                instanceEnToKrCache[candidateID] = enToKr
            }
            let blizzardEnglishSet = Set(enToKr.keys)
            let overlap = requestedEnglishSet.intersection(blizzardEnglishSet).count
            print("[HG-NR-DEBUG]   후보 \(candidateID): EN→KR \(enToKr.count)개, 영문명 \(blizzardEnglishSet) → overlap=\(overlap)")
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestInstanceID = candidateID
                bestEnToKr = enToKr
            }
        }

        guard let chosen = bestInstanceID, bestOverlap > 0 else {
            print("[HG-NR-DEBUG] ❌ 어떤 후보도 WCL 영문명과 겹치지 않음 — 영문 유지")
            logger.warning("'\(dungeonKoreanName)' 번역 실패: \(candidateIDs.count)개 후보 중 겹치는 보스 없음")
            return [:]
        }
        print("[HG-NR-DEBUG] ✅ 최적 후보: instanceID=\(chosen), overlap=\(bestOverlap)")
        dungeonInstanceIDCache[dungeonKoreanName] = chosen

        // 3. WCL encID → 한국어 이름 매핑 (영문명 매칭)
        var result: [Int: String] = [:]
        var unmatched: [String] = []
        for (wclEncID, englishName) in englishNames {
            if let korean = bestEnToKr[englishName], !korean.isEmpty {
                result[wclEncID] = korean
            } else {
                unmatched.append(englishName)
            }
        }
        print("[HG-NR-DEBUG] 최종 번역 결과: \(result.count)개 성공 / \(unmatched.count)개 실패")
        if !unmatched.isEmpty {
            print("[HG-NR-DEBUG]   매칭 실패 영문명: \(unmatched)")
        }
        return result
    }

    // 던전 한국어명에 매칭되는 모든 instanceID 반환 (정확 일치 우선).
    private func findInstanceIDs(dungeonKoreanName: String, token: String) async -> [Int] {
        // index 스캔 1회만
        if journalIndexKR == nil {
            do {
                journalIndexKR = try await blizzardClient.fetchJournalInstanceIndex(
                    locale: "ko_KR", token: token
                )
            } catch {
                logger.warning("journal-instance/index 페치 실패: \(error)")
                return []
            }
        }
        guard let index = journalIndexKR else { return [] }
        let trimmed = dungeonKoreanName.trimmingCharacters(in: .whitespaces)
        // 정확 일치 전부 → 부분 일치 전부 (중복 제거) 순서로 수집
        let exactMatches = index.filter { $0.name == dungeonKoreanName }.map(\.instanceID)
        if !exactMatches.isEmpty { return exactMatches }
        let partialMatches = index
            .filter { $0.name.contains(trimmed) || trimmed.contains($0.name) }
            .map(\.instanceID)
        return partialMatches
    }

    private func fetchEnToKrMap(instanceID: Int, token: String) async -> [String: String] {
        async let enFetch = fetchInstanceEncounters(instanceID: instanceID, locale: "en_US", token: token)
        async let krFetch = fetchInstanceEncounters(instanceID: instanceID, locale: "ko_KR", token: token)
        let (enList, krList) = await (enFetch, krFetch)
        guard !enList.isEmpty, !krList.isEmpty else { return [:] }

        // 같은 Blizzard encounterID 기준으로 매칭
        let krByID = Dictionary(uniqueKeysWithValues: krList.map { ($0.encounterID, $0.name) })
        var result: [String: String] = [:]
        for en in enList {
            if let kr = krByID[en.encounterID], !kr.isEmpty {
                result[en.name] = kr
            }
        }
        return result
    }

    private func fetchInstanceEncounters(instanceID: Int, locale: String, token: String) async -> [JournalEncounterSummary] {
        do {
            let info = try await blizzardClient.fetchJournalInstance(
                instanceID: instanceID, locale: locale, token: token
            )
            return info.encounters
        } catch {
            logger.warning("journal-instance/\(instanceID) (\(locale, privacy: .public)) 페치 실패: \(error)")
            return []
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
    var stubbedTranslations: [Int: String] = [:]

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

    func translateEncountersToKorean(
        dungeonKoreanName: String,
        englishNames:      [Int: String],
        blizzardClientID:     String,
        blizzardClientSecret: String
    ) async -> [Int: String] {
        stubbedTranslations.filter { englishNames.keys.contains($0.key) }
    }
}
