import XCTest
@testable import HealGuide

final class RankerDataMergerTests: XCTestCase {
    private let merger = RankerDataMergerImpl()

    // MARK: - WelfordAccumulator

    func test_welford_singleValue_zeroStddev() {
        var acc = WelfordAccumulator()
        acc.update(3.0)
        XCTAssertEqual(acc.mean,   3.0, accuracy: 0.001)
        XCTAssertEqual(acc.stddev, 0.0, accuracy: 0.001)
    }

    func test_welford_twoValues_correctMeanAndStddev() {
        var acc = WelfordAccumulator()
        acc.update(2.0)
        acc.update(4.0)
        XCTAssertEqual(acc.mean,   3.0, accuracy: 0.001)
        // sample stddev = sqrt(((2-3)^2 + (4-3)^2) / 1) = sqrt(2) ≈ 1.414
        XCTAssertEqual(acc.stddev, 1.414, accuracy: 0.001)
    }

    func test_welford_multipleValues() {
        var acc = WelfordAccumulator()
        [1.0, 2.0, 3.0, 4.0, 5.0].forEach { acc.update($0) }
        XCTAssertEqual(acc.mean,  3.0, accuracy: 0.001)
        // sample stddev = sqrt(10/4) = sqrt(2.5) ≈ 1.581
        XCTAssertEqual(acc.stddev, 1.581, accuracy: 0.001)
    }

    // MARK: - RankerDataMerger 다수결

    func test_merge_quorumFilter_belowThreshold_excluded() {
        // 10파스 중 4파스만 특정 조합 → ⌈10/2⌉=5 미달 → 제외
        let parses = (0..<10).map { index -> (parse: RankerParse, bossPairs: [BossHealPair]) in
            let pairs: [BossHealPair] = index < 4 ? [
                BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 500, delaySeconds: 2.0)
            ] : []
            return (parse: makeParse(id: "\(index)"), bossPairs: pairs)
        }

        let data = merger.merge(parses: parses, meta: dummyMeta())
        XCTAssertNil(data.encounterData[100]?[1], "4/10 파스는 다수결 미달로 제외돼야 함")
    }

    func test_merge_quorumFilter_atThreshold_included() {
        // 10파스 중 5파스 → ⌈10/2⌉=5 → 포함
        let parses = (0..<10).map { index -> (parse: RankerParse, bossPairs: [BossHealPair]) in
            let pairs: [BossHealPair] = index < 5 ? [
                BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 500, delaySeconds: 2.0)
            ] : []
            return (parse: makeParse(id: "\(index)"), bossPairs: pairs)
        }

        let data = merger.merge(parses: parses, meta: dummyMeta())
        let entries = data.encounterData[100]?[1]
        XCTAssertNotNil(entries, "5/10 파스는 다수결 충족으로 포함돼야 함")
        XCTAssertEqual(entries?.first?.spellID, 500)
        XCTAssertEqual(entries?.first?.count, 5)
        XCTAssertEqual(entries?.first?.quorum, "5/10")
    }

    func test_merge_multipleSpellsForOneBoss_allIncluded() {
        // 보스 스킬 1에 힐 스킬 500, 501 두 가지 — 둘 다 다수결 충족
        let parses: [(parse: RankerParse, bossPairs: [BossHealPair])] = (0..<4).map { index in
            (
                parse: makeParse(id: "\(index)"),
                bossPairs: [
                    BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 500, delaySeconds: 1.0),
                    BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 501, delaySeconds: 2.0),
                ]
            )
        }

        let data = merger.merge(parses: parses, meta: dummyMeta())
        let entries = data.encounterData[100]?[1]
        XCTAssertEqual(entries?.count, 2, "힐 스킬 2개 모두 포함돼야 함")
    }

    func test_merge_welfordAveraging() throws {
        // 4파스 — delay 1.0, 2.0, 3.0, 4.0 → mean = 2.5
        let delays: [Double] = [1.0, 2.0, 3.0, 4.0]
        let parses: [(parse: RankerParse, bossPairs: [BossHealPair])] = delays.enumerated().map { index, delay in
            (
                parse: makeParse(id: "\(index)"),
                bossPairs: [
                    BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 500, delaySeconds: delay)
                ]
            )
        }

        let data = merger.merge(parses: parses, meta: dummyMeta())
        let entry = try XCTUnwrap(data.encounterData[100]?[1]?.first)
        XCTAssertEqual(entry.delay,  2.5,   accuracy: 0.001, "delay 평균이 2.5여야 함")
        XCTAssertEqual(entry.count,  4)
        XCTAssertEqual(entry.quorum, "4/4")
    }

    func test_merge_emptyParses_returnsEmptyData() {
        let data = merger.merge(parses: [], meta: dummyMeta())
        XCTAssertTrue(data.encounterData.isEmpty)
    }

    func test_merge_sortedByDelay() {
        // 두 힐 스킬 중 delay 큰 것이 두 번째에 위치해야 함
        let parses: [(parse: RankerParse, bossPairs: [BossHealPair])] = (0..<4).map { index in
            (
                parse: makeParse(id: "\(index)"),
                bossPairs: [
                    BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 502, delaySeconds: 5.0),
                    BossHealPair(encounterID: 100, bossSpellID: 1, healSpellID: 501, delaySeconds: 1.0),
                ]
            )
        }

        let data = merger.merge(parses: parses, meta: dummyMeta())
        let entries = data.encounterData[100]?[1]
        XCTAssertEqual(entries?.first?.spellID, 501, "delay 낮은 항목이 먼저 와야 함")
        XCTAssertEqual(entries?.last?.spellID,  502)
    }

    // MARK: - Helpers

    private func makeParse(id: String) -> RankerParse {
        RankerParse(
            id: id,
            reportCode: "testcode",
            fightID: 1,
            talentNodeIDs: [],
            characterName: "TestChar"
        )
    }

    private func dummyMeta() -> HGPTRankerDataMeta {
        HGPTRankerDataMeta(
            version:              1,
            collectedAt:          "2026-04-20T14:30:00+09:00",
            region:               "KR",
            dungeonID:            12648,
            dungeonName:          "어둠꽃 열곡",
            difficulty:           "Mythic+",
            spec:                 "DiscPriest",
            rankersRequested:     10,
            rankersUsed:          10,
            talentFilterPreset:   "",
            talentFilterString:   nil,
            talentFilterSimilarity: 0.0
        )
    }
}
