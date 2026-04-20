import XCTest
@testable import HealGuide

final class TalentFilterServiceTests: XCTestCase {
    private let service = TalentFilterServiceImpl()

    // MARK: - Jaccard Similarity

    func test_jaccard_identicalSets_returnsOne() {
        let set: Set<Int> = [100, 200, 300]
        XCTAssertEqual(service.jaccardSimilarity(set, set), 1.0, accuracy: 0.001)
    }

    func test_jaccard_disjointSets_returnsZero() {
        let a: Set<Int> = [1, 2, 3]
        let b: Set<Int> = [4, 5, 6]
        XCTAssertEqual(service.jaccardSimilarity(a, b), 0.0, accuracy: 0.001)
    }

    func test_jaccard_halfOverlap() {
        let a: Set<Int> = [1, 2, 3, 4]
        let b: Set<Int> = [3, 4, 5, 6]
        // intersection = {3,4}, union = {1,2,3,4,5,6} → 2/6 ≈ 0.333
        XCTAssertEqual(service.jaccardSimilarity(a, b), 2.0 / 6.0, accuracy: 0.001)
    }

    func test_jaccard_emptySets_returnsOne() {
        XCTAssertEqual(service.jaccardSimilarity([], []), 1.0, accuracy: 0.001)
    }

    func test_jaccard_oneEmptySet_returnsZero() {
        let a: Set<Int> = [1, 2]
        XCTAssertEqual(service.jaccardSimilarity(a, []), 0.0, accuracy: 0.001)
    }

    // MARK: - Preset Filter (Method C)

    func test_presetFilter_emptyCoreTalents_passesAll() {
        let preset = TalentPreset(
            id: "test",
            specKey: .discPriest,
            name: "Empty",
            coreTalentNodeIDs: [],
            excludeTalentNodeIDs: []
        )
        let parse = makeParse(talents: [1, 2, 3])
        let result = service.filter([parse], using: TalentFilterConfig(
            preset: preset, talentString: nil, jaccardThreshold: 0.8
        ))
        XCTAssertEqual(result.count, 1)
    }

    func test_presetFilter_coreNotSatisfied_fails() {
        let preset = TalentPreset(
            id: "test",
            specKey: .discPriest,
            name: "Evangelism",
            coreTalentNodeIDs: [100, 200, 999],
            excludeTalentNodeIDs: []
        )
        let parse = makeParse(talents: [100, 200, 300])  // 999 없음
        let result = service.filter([parse], using: TalentFilterConfig(
            preset: preset, talentString: nil, jaccardThreshold: 0.8
        ))
        XCTAssertEqual(result.count, 0)
    }

    func test_presetFilter_coreSatisfied_passes() {
        let preset = TalentPreset(
            id: "test",
            specKey: .discPriest,
            name: "Evangelism",
            coreTalentNodeIDs: [100, 200],
            excludeTalentNodeIDs: []
        )
        let parse = makeParse(talents: [100, 200, 300])
        let result = service.filter([parse], using: TalentFilterConfig(
            preset: preset, talentString: nil, jaccardThreshold: 0.8
        ))
        XCTAssertEqual(result.count, 1)
    }

    func test_presetFilter_excludedPresent_fails() {
        let preset = TalentPreset(
            id: "test",
            specKey: .discPriest,
            name: "Evangelism",
            coreTalentNodeIDs: [100],
            excludeTalentNodeIDs: [999]
        )
        let parse = makeParse(talents: [100, 999])  // 999 포함 → 탈락
        let result = service.filter([parse], using: TalentFilterConfig(
            preset: preset, talentString: nil, jaccardThreshold: 0.8
        ))
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - AND 조건

    func test_andCondition_bothActive_mustPassBoth() {
        let preset = TalentPreset(
            id: "test",
            specKey: .discPriest,
            name: "Evangelism",
            coreTalentNodeIDs: [100],
            excludeTalentNodeIDs: []
        )
        // 프리셋 통과 + 스트링은 파싱 실패(nil) → 필터에서 false 반환
        let parse = makeParse(talents: [100, 200])
        let config = TalentFilterConfig(
            preset: preset,
            talentString: "INVALID_STRING",
            jaccardThreshold: 0.8
        )
        let result = service.filter([parse], using: config)
        XCTAssertEqual(result.count, 0, "파싱 실패 스트링은 안전 실패(false)를 반환해야 함")
    }

    func test_filter_noFilters_passesAll() {
        let parses = [makeParse(talents: [1]), makeParse(talents: [2]), makeParse(talents: [3])]
        let config = TalentFilterConfig(preset: nil, talentString: nil, jaccardThreshold: 0.8)
        let result = service.filter(parses, using: config)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - 탤런트 스트링 파싱 (기본 케이스)

    func test_parseTalentString_emptyString_returnsNil() {
        XCTAssertNil(service.parseTalentString(""))
        XCTAssertNil(service.parseTalentString("   "))
    }

    func test_parseTalentString_invalidBase64_returnsNil() {
        XCTAssertNil(service.parseTalentString("!@#$%^&*"))
    }

    // MARK: - Helpers

    private func makeParse(talents: [Int]) -> RankerParse {
        RankerParse(
            id: UUID().uuidString,
            reportCode: "abc123",
            fightID: 1,
            talentNodeIDs: Set(talents),
            characterName: "TestChar"
        )
    }
}
