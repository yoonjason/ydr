import XCTest
@testable import HealGuide

final class TimelineNormalizerTests: XCTestCase {
    private let normalizer = TimelineNormalizer()

    // MARK: - absolute (플레이어 캐스트의 encounterStart 기준 오프셋)

    func test_absolute_empty_whenNoPlayerCasts() {
        let (absolute, _, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [], playerCasts: [], maxWindow: 30
        )
        XCTAssertTrue(absolute.isEmpty)
    }

    func test_absolute_offsetRelativeToEncounterStart() {
        let player = CastEvent(timestamp: 5_000, spellID: 200, sourceID: 5)
        let (absolute, _, _) = normalizer.normalize(
            encounterStart: 2_000, encounterEnd: 60_000,
            bossCasts: [], playerCasts: [player], maxWindow: 30
        )
        XCTAssertEqual(absolute.count, 1)
        XCTAssertEqual(absolute[0].spellID, 200)
        XCTAssertEqual(absolute[0].offset, 3.0, accuracy: 0.001)
    }

    func test_absolute_multiplePlayerCasts_allIncluded() {
        let casts = [
            CastEvent(timestamp: 0, spellID: 200, sourceID: 5),
            CastEvent(timestamp: 10_000, spellID: 201, sourceID: 5),
            CastEvent(timestamp: 20_500, spellID: 202, sourceID: 5)
        ]
        let (absolute, _, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [], playerCasts: casts, maxWindow: 30
        )
        XCTAssertEqual(absolute.count, 3)
        XCTAssertEqual(absolute[2].offset, 20.5, accuracy: 0.001)
    }

    // MARK: - leadIns (보스 캐스트 이전 15초 램프 시퀀스)

    func test_leadIns_empty_whenNoPlayerCasts() {
        let boss = CastEvent(timestamp: 10_000, spellID: 100, sourceID: 1)
        let (_, _, leadIns) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [], maxWindow: 30
        )
        XCTAssertTrue(leadIns.isEmpty)
    }

    func test_leadIns_playerWithinWindow_negativeOffset() {
        let boss = CastEvent(timestamp: 20_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 12_000, spellID: 200, sourceID: 5)  // 8초 전
        let (_, _, leadIns) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertEqual(leadIns.count, 1)
        XCTAssertEqual(leadIns[0].bossAbilityID, 100)
        XCTAssertEqual(leadIns[0].playerSpellID, 200)
        XCTAssertEqual(leadIns[0].offset, -8.0, accuracy: 0.001)
    }

    func test_leadIns_playerOutsideWindow_excluded() {
        let boss = CastEvent(timestamp: 30_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 10_000, spellID: 200, sourceID: 5)  // 20초 전 (윈도우 15초)
        let (_, _, leadIns) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertTrue(leadIns.isEmpty)
    }

    func test_leadIns_playerAtBossCast_excluded() {
        // boss 와 동시점 또는 이후는 leadIn 에 포함 안 됨 (reactions 영역)
        let boss = CastEvent(timestamp: 10_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 10_000, spellID: 200, sourceID: 5)
        let (_, _, leadIns) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertTrue(leadIns.isEmpty)
    }

    func test_leadIns_multiplePlayerCasts_sortedByTime() {
        let boss = CastEvent(timestamp: 20_000, spellID: 100, sourceID: 1)
        let p1 = CastEvent(timestamp: 10_000, spellID: 201, sourceID: 5)  // -10s
        let p2 = CastEvent(timestamp: 15_000, spellID: 202, sourceID: 5)  // -5s
        let p3 = CastEvent(timestamp: 8_000,  spellID: 203, sourceID: 5)  // -12s
        let (_, _, leadIns) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [p1, p2, p3], maxWindow: 30
        )
        XCTAssertEqual(leadIns.count, 3)
        XCTAssertEqual(leadIns[0].playerSpellID, 203)  // -12s 먼저
        XCTAssertEqual(leadIns[1].playerSpellID, 201)  // -10s
        XCTAssertEqual(leadIns[2].playerSpellID, 202)  // -5s
    }

    // MARK: - reactions

    func test_reactions_empty_whenNoPlayerCasts() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [], maxWindow: 30
        )
        XCTAssertTrue(reactions.isEmpty)
    }

    func test_reactions_playerWithinWindow_included() {
        let boss = CastEvent(timestamp: 1_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 3_000, spellID: 200, sourceID: 5)
        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertEqual(reactions.count, 1)
        XCTAssertEqual(reactions[0].bossAbilityID, 100)
        XCTAssertEqual(reactions[0].playerSpellID, 200)
        XCTAssertEqual(reactions[0].delay, 2.0, accuracy: 0.001)
    }

    func test_reactions_playerBeyondWindow_excluded() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 31_000, spellID: 200, sourceID: 5)
        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertTrue(reactions.isEmpty)
    }

    func test_reactions_playerBeforeBoss_excluded() {
        let boss = CastEvent(timestamp: 5_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 4_000, spellID: 200, sourceID: 5)
        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertTrue(reactions.isEmpty)
    }

    func test_reactions_playerAtWindowBoundary_included() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 30_000, spellID: 200, sourceID: 5)
        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertEqual(reactions.count, 1)
        XCTAssertEqual(reactions[0].delay, 30.0, accuracy: 0.001)
    }

    func test_reactions_multipleBossCasts_eachMatchesSeparately() {
        let boss1 = CastEvent(timestamp: 1_000, spellID: 100, sourceID: 1)
        let boss2 = CastEvent(timestamp: 50_000, spellID: 101, sourceID: 1)
        let player1 = CastEvent(timestamp: 2_000, spellID: 200, sourceID: 5)
        let player2 = CastEvent(timestamp: 51_000, spellID: 201, sourceID: 5)

        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss1, boss2], playerCasts: [player1, player2], maxWindow: 30
        )
        XCTAssertEqual(reactions.count, 2)
    }

    func test_reactions_delayMillisecondPrecision() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 2_500, spellID: 200, sourceID: 5)
        let (_, reactions, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertEqual(reactions[0].delay, 2.5, accuracy: 0.001)
    }
}
