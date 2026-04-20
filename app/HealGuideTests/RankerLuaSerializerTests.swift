import XCTest
@testable import HealGuide

final class RankerLuaSerializerTests: XCTestCase {

    private let serializer = RankerLuaSerializer()

    // MARK: - Fixtures

    private func makeMeta(
        spec: String = "DiscPriest",
        dungeonID: Int = 12660,
        difficulty: String = "Mythic+",
        rankersUsed: Int = 8
    ) -> HGPTRankerDataMeta {
        HGPTRankerDataMeta(
            version: 1,
            collectedAt: "2026-04-20T14:30:00+09:00",
            region: "KR",
            dungeonID: dungeonID,
            dungeonName: "테스트 던전",
            difficulty: difficulty,
            spec: spec,
            rankersRequested: 10,
            rankersUsed: rankersUsed,
            talentFilterPreset: "Evangelism",
            talentFilterString: false,
            talentFilterSimilarity: 0.0
        )
    }

    private func makeEntry(
        spec: String = "DiscPriest",
        dungeonID: Int = 12660,
        difficulty: String = "Mythic+",
        rankersUsed: Int = 8,
        encounterNames: [Int: String] = [:]
    ) -> HGPTRankerData {
        HGPTRankerData(
            meta: makeMeta(spec: spec, dungeonID: dungeonID, difficulty: difficulty, rankersUsed: rankersUsed),
            encounterData: [
                2902: [
                    440802: [
                        RankerResponseEntry(spellID: 33206, delay: 2.3, stddev: 0.4, count: 8, quorum: "8/10")
                    ]
                ]
            ],
            encounterNames: encounterNames
        )
    }

    private func tempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rankerCacheTest-\(UUID().uuidString).json")
    }

    // MARK: - Serializer Tests

    func test_singleEntry_producesOptionBStructure() {
        let output = serializer.serialize([makeEntry()])

        XCTAssertTrue(output.contains("HGPT_RankerData = {"))
        XCTAssertTrue(output.contains("entries = {"))
        XCTAssertTrue(output.contains("_meta = {"))
        XCTAssertTrue(output.contains("data = {"))
        // Option A 평탄 구조가 출력되면 안 됨
        XCTAssertFalse(output.hasPrefix("HGPT_RankerData = {\n    _meta"))
        XCTAssertFalse(output.contains("HGPT_RankerData = {\n    _meta"))
    }

    func test_singleEntry_metaFieldsPresent() {
        let output = serializer.serialize([makeEntry(spec: "DiscPriest", dungeonID: 12660)])

        XCTAssertTrue(output.contains("spec             = \"DiscPriest\""))
        XCTAssertTrue(output.contains("dungeonID        = 12660"))
        XCTAssertTrue(output.contains("collectedAt      = \"2026-04-20T14:30:00+09:00\""))
    }

    func test_singleEntry_dataFieldsPresent() {
        let output = serializer.serialize([makeEntry()])

        XCTAssertTrue(output.contains("[2902] = {"))
        XCTAssertTrue(output.contains("[440802] = {"))
        XCTAssertTrue(output.contains("spellID = 33206"))
        XCTAssertTrue(output.contains("delay   = 2.30"))
        XCTAssertTrue(output.contains("quorum  = \"8/10\""))
    }

    func test_multipleEntries_allIncludedInEntriesArray() {
        let entry1 = makeEntry(spec: "DiscPriest")
        let entry2 = makeEntry(spec: "HolyPriest")
        let output = serializer.serialize([entry1, entry2])

        let specOccurrences = output.components(separatedBy: "spec             = ").count - 1
        XCTAssertEqual(specOccurrences, 2, "entries 배열에 두 스펙 모두 포함되어야 함")
        XCTAssertTrue(output.contains("spec             = \"DiscPriest\""))
        XCTAssertTrue(output.contains("spec             = \"HolyPriest\""))
    }

    func test_emptyEntries_producesValidLuaWithEmptyArray() {
        let output = serializer.serialize([])

        XCTAssertTrue(output.contains("entries = {"))
        XCTAssertTrue(output.contains("HGPT_RankerData = {"))
        XCTAssertFalse(output.contains("_meta"))
    }

    func test_luaEscaping_quotesAndBackslashesEscaped() {
        let metaWithSpecialChars = HGPTRankerDataMeta(
            version: 1,
            collectedAt: "2026-04-20T14:30:00+09:00",
            region: "KR",
            dungeonID: 1,
            dungeonName: "던전 \"따옴표\" \\역슬래시\\",
            difficulty: "Mythic+",
            spec: "DiscPriest",
            rankersRequested: 10,
            rankersUsed: 8,
            talentFilterPreset: "",
            talentFilterString: false,
            talentFilterSimilarity: 0.0
        )
        let entry = HGPTRankerData(meta: metaWithSpecialChars, encounterData: [:], encounterNames: [:])
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("\\\"따옴표\\\""), "큰따옴표가 이스케이프되어야 함")
        XCTAssertTrue(output.contains("\\\\역슬래시\\\\"), "역슬래시가 이스케이프되어야 함")
    }

    // MARK: - Encounter Name (_name) Tests

    func test_encounterName_presentWhenResolved() {
        let entry = makeEntry(encounterNames: [2902: "울그루가시"])
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("_name = \"울그루가시\""), "_name 필드가 한국어 이름으로 출력되어야 함")
        // 이름 줄은 encID 블록 안에 있어야 함
        let nameRange = output.range(of: "_name = \"울그루가시\"")
        let encRange  = output.range(of: "[2902] = {")
        XCTAssertNotNil(nameRange)
        XCTAssertNotNil(encRange)
        if let nr = nameRange, let er = encRange {
            XCTAssertTrue(er.lowerBound < nr.lowerBound, "_name 은 해당 encID 블록 내부에 있어야 함")
        }
    }

    func test_encounterName_absentWhenNotResolved() {
        let entry = makeEntry(encounterNames: [:])
        let output = serializer.serialize([entry])

        XCTAssertFalse(output.contains("_name"), "이름 미해상 시 _name 필드 자체가 없어야 함")
    }

    func test_encounterName_luaEscaped() {
        let entry = makeEntry(encounterNames: [2902: "보스 \"따옴표\""])
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("_name = \"보스 \\\"따옴표\\\"\""), "이름 내 따옴표가 이스케이프되어야 함")
    }

    func test_encounterName_onlyPresentForMatchingEncounter() {
        let meta = makeMeta()
        let entry = HGPTRankerData(
            meta: meta,
            encounterData: [
                2902: [440802: [RankerResponseEntry(spellID: 33206, delay: 1.0, stddev: 0.1, count: 5, quorum: "5/10")]],
                9999: [123456: [RankerResponseEntry(spellID: 64843, delay: 2.0, stddev: 0.2, count: 5, quorum: "5/10")]]
            ],
            encounterNames: [2902: "울그루가시"]  // 9999는 이름 없음
        )
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("_name = \"울그루가시\""), "이름이 있는 encounter 는 _name 출력")
        // encounter 9999 블록에는 _name 이 없어야 함.
        // 출력 전체에서 _name 출현 횟수가 정확히 1 (=2902 분만) 인지 확인.
        let nameMatches = output.components(separatedBy: "_name").count - 1
        XCTAssertEqual(nameMatches, 1, "_name 은 이름이 있는 encounter 에서만 1회 출력되어야 함")
    }

    // MARK: - Cache Service Tests

    func test_cacheService_sameKey_replacesExistingEntry() {
        let url = tempCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = RankerCacheService(cacheURL: url)
        _ = cache.merge(makeEntry(spec: "DiscPriest", dungeonID: 12660, difficulty: "Mythic+", rankersUsed: 8))

        let updated = makeEntry(spec: "DiscPriest", dungeonID: 12660, difficulty: "Mythic+", rankersUsed: 10)
        let merged = cache.merge(updated)

        XCTAssertEqual(merged.count, 1, "같은 키는 교체 후 1개여야 함")
        XCTAssertEqual(merged[0].meta.rankersUsed, 10, "최신 entry 로 교체되어야 함")
    }

    func test_cacheService_differentSpec_appendsEntry() {
        let url = tempCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = RankerCacheService(cacheURL: url)
        _ = cache.merge(makeEntry(spec: "DiscPriest"))
        let merged = cache.merge(makeEntry(spec: "HolyPriest"))

        XCTAssertEqual(merged.count, 2, "다른 spec 은 append 되어야 함")
    }

    func test_cacheService_differentDungeon_appendsEntry() {
        let url = tempCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = RankerCacheService(cacheURL: url)
        _ = cache.merge(makeEntry(dungeonID: 12660))
        let merged = cache.merge(makeEntry(dungeonID: 13161))

        XCTAssertEqual(merged.count, 2, "다른 dungeonID 는 append 되어야 함")
    }

    func test_cacheService_differentDifficulty_appendsEntry() {
        let url = tempCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = RankerCacheService(cacheURL: url)
        _ = cache.merge(makeEntry(difficulty: "Mythic+"))
        let merged = cache.merge(makeEntry(difficulty: "Heroic"))

        XCTAssertEqual(merged.count, 2, "다른 difficulty 는 append 되어야 함")
    }

    func test_cacheService_persistsAcrossInstances() {
        let url = tempCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cache1 = RankerCacheService(cacheURL: url)
        _ = cache1.merge(makeEntry(spec: "DiscPriest"))
        _ = cache1.merge(makeEntry(spec: "HolyPriest"))

        let cache2 = RankerCacheService(cacheURL: url)
        let loaded = cache2.merge(makeEntry(spec: "RestoShaman"))

        XCTAssertEqual(loaded.count, 3, "캐시 파일에서 기존 entries 를 복원해야 함")
    }
}
