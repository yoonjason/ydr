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

    // MARK: - isSaved / hasUnsavedPreview 불변식

    func test_hasUnsavedPreview_true_afterPreviewWithoutSave() {
        let viewModel = makeViewModel()
        viewModel.state = .preview(dummyPreview(), dummyData())
        XCTAssertFalse(viewModel.isSaved, "초기 진입 시 isSaved 는 false")
        XCTAssertTrue(viewModel.hasUnsavedPreview, "preview 상태이고 저장 전이면 미저장")
    }

    func test_hasUnsavedPreview_false_inIdleState() {
        let viewModel = makeViewModel()
        viewModel.state = .idle
        viewModel.isSaved = true
        XCTAssertFalse(viewModel.hasUnsavedPreview, "preview 상태가 아니면 미저장 표시 없음")
    }

    func test_startCollect_resetsIsSavedFlag() {
        let viewModel = makeViewModel()
        viewModel.isSaved = true
        viewModel.startCollect()
        XCTAssertFalse(viewModel.isSaved, "startCollect 호출 시 isSaved 는 false 로 리셋")
    }

    func test_reset_clearsIsSavedFlag() {
        let viewModel = makeViewModel()
        viewModel.isSaved = true
        viewModel.reset()
        XCTAssertFalse(viewModel.isSaved, "reset 호출 시 isSaved 는 false 로 리셋")
    }

    // MARK: - B-6: buildPairs 정렬 + 조기 종료 엣지 케이스

    func test_buildPairs_reversedInput_correctDelay() {
        let bossCast = CastEvent(timestamp: 1000, spellID: 101, sourceID: 1)
        // 역순 입력: 최신 timestamp 먼저
        let healerCasts = [
            CastEvent(timestamp: 5000, spellID: 202, sourceID: 2),
            CastEvent(timestamp: 2000, spellID: 201, sourceID: 2),
        ]
        let pairs = RankerCollectionViewModel.buildPairs(
            encounterID: 1,
            bossCasts:   [bossCast],
            healerCasts: healerCasts,
            windowStart: 0
        )
        XCTAssertEqual(pairs.count, 1)
        // 정렬 후 가장 빠른 healerCast(2000)가 선택되어야 함
        XCTAssertEqual(pairs[0].healSpellID, 201)
        XCTAssertEqual(pairs[0].delaySeconds, 1.0, accuracy: 0.001)
    }

    func test_buildPairs_multipleHealCastsAtSameTimestamp_firstSelected() {
        let bossCast = CastEvent(timestamp: 0, spellID: 101, sourceID: 1)
        let healerCasts = [
            CastEvent(timestamp: 500, spellID: 201, sourceID: 2),
            CastEvent(timestamp: 500, spellID: 202, sourceID: 2),
        ]
        let pairs = RankerCollectionViewModel.buildPairs(
            encounterID: 1,
            bossCasts:   [bossCast],
            healerCasts: healerCasts,
            windowStart: 0
        )
        XCTAssertEqual(pairs.count, 1, "동일 timestamp 다수여도 첫 번째 1개만 선택")
    }

    func test_buildPairs_emptyHealerCasts_returnsEmpty() {
        let bossCast = CastEvent(timestamp: 1000, spellID: 101, sourceID: 1)
        let pairs = RankerCollectionViewModel.buildPairs(
            encounterID: 1,
            bossCasts:   [bossCast],
            healerCasts: [],
            windowStart: 0
        )
        XCTAssertTrue(pairs.isEmpty, "healerCasts가 빈 배열이면 pairs도 빈 배열")
    }

    func test_buildPairs_healCastsAllOutsideWindow_earlyTermination() {
        let bossCast = CastEvent(timestamp: 0, spellID: 101, sourceID: 1)
        // 모두 30초(30000ms) 이후
        let healerCasts = [
            CastEvent(timestamp: 30_001, spellID: 201, sourceID: 2),
            CastEvent(timestamp: 60_000, spellID: 202, sourceID: 2),
        ]
        let pairs = RankerCollectionViewModel.buildPairs(
            encounterID: 1,
            bossCasts:   [bossCast],
            healerCasts: healerCasts,
            windowStart: 0
        )
        XCTAssertTrue(pairs.isEmpty, "윈도우 이후 모든 캐스트는 조기 종료로 스킵")
    }

    func test_buildPairs_healCastExactlyAtWindowBoundary_included() {
        let bossCast = CastEvent(timestamp: 0, spellID: 101, sourceID: 1)
        let healerCasts = [
            CastEvent(timestamp: 30_000, spellID: 201, sourceID: 2),  // 정확히 upperBound
        ]
        let pairs = RankerCollectionViewModel.buildPairs(
            encounterID: 1,
            bossCasts:   [bossCast],
            healerCasts: healerCasts,
            windowStart: 0
        )
        XCTAssertEqual(pairs.count, 1, "upperBound와 동일한 timestamp는 포함")
        XCTAssertEqual(pairs[0].delaySeconds, 30.0, accuracy: 0.001)
    }

    // MARK: - availableDungeons 필터링 (Midnight 시즌 던전 데이터)

    func test_availableDungeons_mythicPlus_returnsAllDungeons() {
        let viewModel = makeViewModel()
        viewModel.selectedDifficulty = .mythicPlus

        XCTAssertEqual(viewModel.availableDungeons.count, DungeonInfo.currentSeason.count,
                       "Mythic+는 전체 던전 반환")
    }

    func test_availableDungeons_heroic_returnsOnlyNormalHeroicDungeons() {
        let viewModel = makeViewModel()
        viewModel.selectedDifficulty = .heroic

        let allSupportNormalHeroic = viewModel.availableDungeons.allSatisfy { $0.supportsNormalHeroic }
        XCTAssertTrue(allSupportNormalHeroic, "영웅 선택 시 supportsNormalHeroic=false 던전 제외")

        let expectedCount = DungeonInfo.currentSeason.filter { $0.supportsNormalHeroic }.count
        XCTAssertEqual(viewModel.availableDungeons.count, expectedCount)
    }

    func test_availableDungeons_normal_returnsOnlyNormalHeroicDungeons() {
        let viewModel = makeViewModel()
        viewModel.selectedDifficulty = .normal

        let allSupportNormalHeroic = viewModel.availableDungeons.allSatisfy { $0.supportsNormalHeroic }
        XCTAssertTrue(allSupportNormalHeroic, "일반 선택 시 supportsNormalHeroic=false 던전 제외")
    }

    func test_availableDungeons_recycledDungeon_excludedOnHeroic() {
        let viewModel = makeViewModel()
        viewModel.selectedDifficulty = .heroic

        // 재활용 던전(쐐기 전용)은 목록에 없어야 함
        let recycledIDs: Set<Int> = [112526, 361753, 61209, 10658]
        let containsRecycled = viewModel.availableDungeons.contains { recycledIDs.contains($0.id) }
        XCTAssertFalse(containsRecycled, "구 확장 재활용 던전은 영웅 선택 시 제외")
    }

    func test_availableDungeons_newDungeon_includedOnHeroic() {
        let viewModel = makeViewModel()
        viewModel.selectedDifficulty = .heroic

        // 한밤 신규 던전은 영웅에서도 노출
        let newDungeonIDs: Set<Int> = [12805, 12811, 12874, 12915]
        let allNewDungeonsPresent = newDungeonIDs.allSatisfy { id in
            viewModel.availableDungeons.contains { $0.id == id }
        }
        XCTAssertTrue(allNewDungeonsPresent, "한밤 신규 던전은 영웅 선택 시 포함")
    }

    func test_resetDungeonSelectionIfNeeded_selectedDungeonOutsideFilter_resetsToFirst() {
        let viewModel = makeViewModel()
        // 재활용 던전(쐐기 전용) 선택
        let recycledDungeon = DungeonInfo.currentSeason.first { !$0.supportsNormalHeroic }
        viewModel.selectedDungeon = recycledDungeon

        // 영웅으로 전환 후 재설정 요청
        viewModel.selectedDifficulty = .heroic
        viewModel.resetDungeonSelectionIfNeeded()

        // 선택이 availableDungeons의 첫 번째 요소로 교체돼야 함
        XCTAssertEqual(viewModel.selectedDungeon, viewModel.availableDungeons.first,
                       "필터 밖 던전 선택 후 난이도 변경 시 첫 번째 요소로 자동 재설정")
    }

    func test_resetDungeonSelectionIfNeeded_selectedDungeonInsideFilter_noChange() {
        let viewModel = makeViewModel()
        let newDungeon = DungeonInfo.currentSeason.first { $0.supportsNormalHeroic }
        viewModel.selectedDungeon = newDungeon

        viewModel.selectedDifficulty = .heroic
        viewModel.resetDungeonSelectionIfNeeded()

        XCTAssertEqual(viewModel.selectedDungeon, newDungeon,
                       "필터 내에 있으면 선택 유지")
    }

    func test_resetDungeonSelectionIfNeeded_nilSelection_noChange() {
        let viewModel = makeViewModel()
        viewModel.selectedDungeon = nil

        viewModel.selectedDifficulty = .heroic
        viewModel.resetDungeonSelectionIfNeeded()

        XCTAssertNil(viewModel.selectedDungeon, "nil 선택은 변경 없음")
    }

    // MARK: - Helpers

    private func makeViewModel(
        filterService: any TalentFilterService,
        merger: any RankerDataMerger
    ) -> RankerCollectionViewModel {
        RankerCollectionViewModel(
            apiClient:      MockWarcraftLogsAPIClient(),
            rankingService: MockCharacterRankingsService(),
            filterService:  filterService,
            merger:         merger,
            keychain:       MockKeychain()
        )
    }

    private func makeViewModel(
        filterService: any TalentFilterService
    ) -> RankerCollectionViewModel {
        makeViewModel(
            filterService: filterService,
            merger: MockRankerDataMerger(mergeResult: dummyData(), buildPreviewResult: dummyPreview())
        )
    }

    private func makeViewModel(
        merger: any RankerDataMerger
    ) -> RankerCollectionViewModel {
        makeViewModel(
            filterService: MockTalentFilterService(filterResult: [], parseTalentStringResult: nil),
            merger: merger
        )
    }

    private func makeViewModel() -> RankerCollectionViewModel {
        makeViewModel(
            filterService: MockTalentFilterService(filterResult: [], parseTalentStringResult: nil),
            merger: MockRankerDataMerger(mergeResult: dummyData(), buildPreviewResult: dummyPreview())
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
            encounterData: [:],
            encounterNames: [:]
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

