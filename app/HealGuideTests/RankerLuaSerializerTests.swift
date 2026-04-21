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
            talentFilterString: nil,
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

    func test_luaEscaping_newlineTabCarriageReturnEscaped() {
        let meta = HGPTRankerDataMeta(
            version: 1,
            collectedAt: "2026-04-20T14:30:00+09:00",
            region: "KR",
            dungeonID: 1,
            dungeonName: "라인1\n라인2",
            difficulty: "Mythic+",
            spec: "DiscPriest",
            rankersRequested: 10,
            rankersUsed: 8,
            talentFilterPreset: "프리셋\t탭",
            talentFilterString: "스트링\r\n개행",
            talentFilterSimilarity: 0.0
        )
        let entry = HGPTRankerData(meta: meta, encounterData: [:], encounterNames: [:])
        let output = serializer.serialize([entry])

        XCTAssertFalse(output.contains("라인1\n라인2"), "이스케이프되지 않은 개행이 없어야 함")
        XCTAssertTrue(output.contains("라인1\\n라인2"), "\\n으로 이스케이프되어야 함")
        XCTAssertTrue(output.contains("프리셋\\t탭"), "\\t으로 이스케이프되어야 함")
        XCTAssertTrue(output.contains("\\r\\n"), "\\r\\n으로 이스케이프되어야 함")
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
            talentFilterString: nil,
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

    // MARK: - Boss Spell Names (_bossNames) Tests

    func test_bossNames_presentWhenPopulated() {
        let meta = makeMeta()
        var entry = HGPTRankerData(
            meta: meta,
            encounterData: [
                2902: [440802: [RankerResponseEntry(spellID: 33206, delay: 2.3, stddev: 0.4, count: 8, quorum: "8/10")]]
            ],
            encounterNames: [:]
        )
        entry.bossSpellNames = [2902: [440802: "화염 충돌"]]
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("_bossNames = {"), "_bossNames 블록이 출력되어야 함")
        XCTAssertTrue(output.contains("[440802] = \"화염 충돌\""), "bossSpellID → 이름 항목이 출력되어야 함")
    }

    func test_bossNames_absentWhenEmpty() {
        let entry = makeEntry()
        let output = serializer.serialize([entry])

        XCTAssertFalse(output.contains("_bossNames"), "bossSpellNames 없으면 _bossNames 블록 출력 금지")
    }

    func test_bossNames_luaEscaped() {
        let meta = makeMeta()
        var entry = HGPTRankerData(
            meta: meta,
            encounterData: [
                2902: [440802: [RankerResponseEntry(spellID: 33206, delay: 1.0, stddev: 0.1, count: 5, quorum: "5/10")]]
            ],
            encounterNames: [:]
        )
        entry.bossSpellNames = [2902: [440802: "\"따옴표\" 스킬"]]
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("\\\"따옴표\\\""), "bossSpellName 내 따옴표가 이스케이프되어야 함")
    }

    func test_bossNames_multipleSpells_sortedByID() {
        let meta = makeMeta()
        var entry = HGPTRankerData(
            meta: meta,
            encounterData: [
                2902: [
                    100: [RankerResponseEntry(spellID: 33206, delay: 1.0, stddev: 0.1, count: 5, quorum: "5/10")],
                    200: [RankerResponseEntry(spellID: 64843, delay: 2.0, stddev: 0.2, count: 5, quorum: "5/10")]
                ]
            ],
            encounterNames: [:]
        )
        entry.bossSpellNames = [2902: [100: "스킬A", 200: "스킬B"]]
        let output = serializer.serialize([entry])

        let idx100 = output.range(of: "[100] = \"스킬A\"")
        let idx200 = output.range(of: "[200] = \"스킬B\"")
        XCTAssertNotNil(idx100)
        XCTAssertNotNil(idx200)
        if let r100 = idx100, let r200 = idx200 {
            XCTAssertTrue(r100.lowerBound < r200.lowerBound, "ID 오름차순으로 출력되어야 함")
        }
    }

    func test_bossNames_onlyForMatchingEncounter() {
        let meta = makeMeta()
        var entry = HGPTRankerData(
            meta: meta,
            encounterData: [
                2902: [440802: [RankerResponseEntry(spellID: 33206, delay: 1.0, stddev: 0.1, count: 5, quorum: "5/10")]],
                9999: [123456: [RankerResponseEntry(spellID: 64843, delay: 2.0, stddev: 0.2, count: 5, quorum: "5/10")]]
            ],
            encounterNames: [:]
        )
        // 2902만 bossSpellNames 있음
        entry.bossSpellNames = [2902: [440802: "화염 충돌"]]
        let output = serializer.serialize([entry])

        let bossNamesCount = output.components(separatedBy: "_bossNames").count - 1
        XCTAssertEqual(bossNamesCount, 1, "_bossNames 는 해당 encounter 블록에서만 1회 출력되어야 함")
    }

    // MARK: - Shared Tactics (_sharedTactics) Tests

    func test_sharedTactics_presentWhenPopulated() {
        var entry = makeEntry()
        entry.sharedTacticalLines = [
            2902: [TacticalLine(priority: .critical, abilityName: "", action: "보스 전체 주의사항")]
        ]
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("_sharedTactics = {"), "_sharedTactics 블록이 출력되어야 함")
        XCTAssertTrue(output.contains("보스 전체 주의사항"), "action 내용이 출력되어야 함")
        XCTAssertTrue(output.contains("priority = \"critical\""), "priority 필드가 출력되어야 함")
    }

    func test_sharedTactics_absentWhenEmpty() {
        let entry = makeEntry()
        let output = serializer.serialize([entry])

        XCTAssertFalse(output.contains("_sharedTactics"), "sharedTacticalLines 없으면 _sharedTactics 출력 금지")
    }

    func test_sharedTactics_appearsBeforeBossSpellBlocks() {
        var entry = makeEntry()
        entry.sharedTacticalLines = [
            2902: [TacticalLine(priority: .note, abilityName: "", action: "주의사항")]
        ]
        let output = serializer.serialize([entry])

        let sharedRange  = output.range(of: "_sharedTactics")
        let bossIDRange  = output.range(of: "[440802]")
        XCTAssertNotNil(sharedRange)
        XCTAssertNotNil(bossIDRange)
        if let sr = sharedRange, let br = bossIDRange {
            XCTAssertTrue(sr.lowerBound < br.lowerBound, "_sharedTactics 는 bossSpellID 블록보다 먼저 출력되어야 함")
        }
    }

    func test_sharedTactics_luaEscaped() {
        var entry = makeEntry()
        entry.sharedTacticalLines = [
            2902: [TacticalLine(priority: .note, abilityName: "", action: "\"따옴표\" 주의")]
        ]
        let output = serializer.serialize([entry])

        XCTAssertTrue(output.contains("\\\"따옴표\\\""), "action 내 따옴표가 이스케이프되어야 함")
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

    // MARK: - talentFilterString Codable 역호환 Tests (S-4)

    func test_metaDecode_legacyBoolFalse_decodesAsNil() throws {
        let json = Data("""
        {"version":1,"collectedAt":"2026-04-20T14:30:00+09:00","region":"KR","dungeonID":12660,
        "dungeonName":"테스트","difficulty":"Mythic+","spec":"DiscPriest","rankersRequested":10,
        "rankersUsed":8,"talentFilterPreset":"","talentFilterString":false,"talentFilterSimilarity":0.0}
        """.utf8)
        let decoded = try JSONDecoder().decode(HGPTRankerDataMeta.self, from: json)
        XCTAssertNil(decoded.talentFilterString, "기존 Bool false → nil 역호환")
    }

    func test_metaDecode_legacyBoolTrue_decodesAsNil() throws {
        let json = Data("""
        {"version":1,"collectedAt":"2026-04-20T14:30:00+09:00","region":"KR","dungeonID":12660,
        "dungeonName":"테스트","difficulty":"Mythic+","spec":"DiscPriest","rankersRequested":10,
        "rankersUsed":8,"talentFilterPreset":"","talentFilterString":true,"talentFilterSimilarity":0.0}
        """.utf8)
        let decoded = try JSONDecoder().decode(HGPTRankerDataMeta.self, from: json)
        XCTAssertNil(decoded.talentFilterString, "기존 Bool true → nil 역호환 (스트링 복원 불가)")
    }

    func test_metaDecode_newStringFormat_preservesValue() throws {
        let json = Data("""
        {"version":1,"collectedAt":"2026-04-20T14:30:00+09:00","region":"KR","dungeonID":12660,
        "dungeonName":"테스트","difficulty":"Mythic+","spec":"DiscPriest","rankersRequested":10,
        "rankersUsed":8,"talentFilterPreset":"","talentFilterString":"ACTUALBASE64STRING","talentFilterSimilarity":0.8}
        """.utf8)
        let decoded = try JSONDecoder().decode(HGPTRankerDataMeta.self, from: json)
        XCTAssertEqual(decoded.talentFilterString, "ACTUALBASE64STRING", "새 String 포맷은 값을 보존해야 함")
    }

    func test_metaEncodeDecode_roundtrip_preservesTalentString() throws {
        let meta = HGPTRankerDataMeta(
            version: 1, collectedAt: "2026-04-20T14:30:00+09:00", region: "KR",
            dungeonID: 12660, dungeonName: "테스트", difficulty: "Mythic+",
            spec: "DiscPriest", rankersRequested: 10, rankersUsed: 8,
            talentFilterPreset: "", talentFilterString: "ROUNDTRIPSTRING",
            talentFilterSimilarity: 0.8
        )
        let encoded = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(HGPTRankerDataMeta.self, from: encoded)
        XCTAssertEqual(decoded.talentFilterString, "ROUNDTRIPSTRING", "인코딩 후 디코딩 시 값 보존")
    }

    // MARK: - Cache Service Tests

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
