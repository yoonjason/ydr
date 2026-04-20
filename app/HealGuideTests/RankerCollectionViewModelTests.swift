import XCTest
@testable import HealGuide

// MARK: - Mock TalentFilterService

private struct MockTalentFilterService: TalentFilterService {
    var filterResult: [RankerParse]
    var parseTalentStringResult: Set<Int>?

    func filter(_ parses: [RankerParse], using config: TalentFilterConfig) -> [RankerParse] {
        return filterResult
    }

    func parseTalentString(_ string: String) -> Set<Int>? {
        return parseTalentStringResult
    }
}

// MARK: - Mock RankerDataMerger

private final class MockRankerDataMerger: RankerDataMerger {
    var mergeResult: HGPTRankerData
    var buildPreviewResult: RankerPreviewResult
    private(set) var buildPreviewCallCount = 0

    init(mergeResult: HGPTRankerData, buildPreviewResult: RankerPreviewResult) {
        self.mergeResult = mergeResult
        self.buildPreviewResult = buildPreviewResult
    }

    func merge(
        parses: [(parse: RankerParse, bossPairs: [BossHealPair])],
        meta: HGPTRankerDataMeta
    ) -> HGPTRankerData {
        return mergeResult
    }

    func buildPreview(
        parsesCollected: Int,
        parsesFiltered: Int,
        data: HGPTRankerData
    ) -> RankerPreviewResult {
        buildPreviewCallCount += 1
        return buildPreviewResult
    }
}

// MARK: - Tests

@MainActor
final class RankerCollectionViewModelTests: XCTestCase {

    // MARK: - B-2: Mock filterService 주입 동작 검증

    func test_validateTalentString_nonEmpty_filterServiceUsed_successPath() {
        let mockFilter = MockTalentFilterService(
            filterResult: [],
            parseTalentStringResult: Set([100, 200])  // 파싱 성공
        )
        let viewModel = makeViewModel(filterService: mockFilter)

        viewModel.talentString = "SomeBase64String"
        viewModel.validateTalentString()

        XCTAssertNil(viewModel.talentParseError, "parseTalentString이 non-nil을 반환하면 에러 없음")
    }

    func test_validateTalentString_nonEmpty_filterServiceUsed_failurePath() {
        let mockFilter = MockTalentFilterService(
            filterResult: [],
            parseTalentStringResult: nil  // 파싱 실패
        )
        let viewModel = makeViewModel(filterService: mockFilter)

        viewModel.talentString = "INVALID"
        viewModel.validateTalentString()

        XCTAssertNotNil(viewModel.talentParseError, "parseTalentString이 nil을 반환하면 에러 메시지 세팅")
    }

    func test_validateTalentString_emptyString_clearsError() {
        let mockFilter = MockTalentFilterService(filterResult: [], parseTalentStringResult: nil)
        let viewModel = makeViewModel(filterService: mockFilter)

        viewModel.talentParseError = "이전 에러"
        viewModel.talentString = "   "
        viewModel.validateTalentString()

        XCTAssertNil(viewModel.talentParseError, "빈 문자열은 에러 클리어")
    }

    // MARK: - B-2: Mock merger 주입 동작 검증

    func test_relaxFilter_inPreviewState_callsMergerBuildPreview() {
        let mockMerger = MockRankerDataMerger(
            mergeResult: dummyData(),
            buildPreviewResult: dummyPreview()
        )
        let viewModel = makeViewModel(merger: mockMerger)

        // .preview 상태로 진입
        viewModel.state = .preview(dummyPreview(), dummyData())
        viewModel.relaxFilter()

        XCTAssertEqual(mockMerger.buildPreviewCallCount, 1, "relaxFilter는 merger.buildPreview를 1회 호출해야 함")
        XCTAssertEqual(viewModel.jaccardThreshold, 0.6, accuracy: 0.001)
    }

    func test_relaxFilter_notInPreviewState_doesNotCallMerger() {
        let mockMerger = MockRankerDataMerger(
            mergeResult: dummyData(),
            buildPreviewResult: dummyPreview()
        )
        let viewModel = makeViewModel(merger: mockMerger)

        // idle 상태
        viewModel.state = .idle
        viewModel.relaxFilter()

        XCTAssertEqual(mockMerger.buildPreviewCallCount, 0, "idle 상태에서는 merger를 호출하지 않음")
    }

    // MARK: - Helpers

    private func makeViewModel(
        filterService: any TalentFilterService = MockTalentFilterService(filterResult: [], parseTalentStringResult: nil),
        merger: any RankerDataMerger = MockRankerDataMerger(mergeResult: RankerCollectionViewModelTests.staticDummyData(), buildPreviewResult: RankerCollectionViewModelTests.staticDummyPreview())
    ) -> RankerCollectionViewModel {
        RankerCollectionViewModel(
            apiClient:      MockWarcraftLogsAPIClient(),
            rankingService: MockCharacterRankingsService(),
            filterService:  filterService,
            merger:         merger,
            keychain:       MockKeychain()
        )
    }

    private func dummyData() -> HGPTRankerData {
        Self.staticDummyData()
    }

    private func dummyPreview() -> RankerPreviewResult {
        Self.staticDummyPreview()
    }

    private static func staticDummyData() -> HGPTRankerData {
        HGPTRankerData(
            meta: HGPTRankerDataMeta(
                version: 1,
                collectedAt: "2026-04-20T00:00:00+09:00",
                region: "KR",
                dungeonID: 12648,
                dungeonName: "어둠꽃 열곡",
                difficulty: "Mythic+",
                spec: "DiscPriest",
                rankersRequested: 10,
                rankersUsed: 5,
                talentFilterPreset: "",
                talentFilterString: false,
                talentFilterSimilarity: 0.0
            ),
            encounterData: [:]
        )
    }

    private static func staticDummyPreview() -> RankerPreviewResult {
        RankerPreviewResult(
            parsesCollected: 10,
            parsesFiltered: 5,
            bossEntries: [],
            highVarianceWarnings: []
        )
    }
}

