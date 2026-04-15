import XCTest
@testable import HealGuide

final class TimelineNormalizerTests: XCTestCase {
    private let normalizer = TimelineNormalizer()

    func test_emptyInputs_returnsEmpty() {
        let result = normalizer.normalize(playerCasts: [], bossCasts: [], windowSeconds: 30)
        XCTAssertTrue(result.isEmpty)
    }

    func test_noPlayerCasts_returnsEmpty() {
        let boss = CastEvent(timestamp: 1000, spellID: 100, sourceID: 1)
        let result = normalizer.normalize(playerCasts: [], bossCasts: [boss], windowSeconds: 30)
        XCTAssertTrue(result.isEmpty)
    }

    func test_playerCastWithinWindow_returnsEntry() {
        let boss = CastEvent(timestamp: 1000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 3000, spellID: 200, sourceID: 5)

        let result = normalizer.normalize(playerCasts: [player], bossCasts: [boss], windowSeconds: 30)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].bossSpellID, 100)
        XCTAssertEqual(result[0].playerSpellID, 200)
        XCTAssertEqual(result[0].delay, 2.0, accuracy: 0.001)
    }

    func test_playerCastBeyondWindow_excluded() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 31_000, spellID: 200, sourceID: 5)  // 31초 뒤

        let result = normalizer.normalize(playerCasts: [player], bossCasts: [boss], windowSeconds: 30)

        XCTAssertTrue(result.isEmpty)
    }

    func test_playerCastBeforeBoss_excluded() {
        let boss = CastEvent(timestamp: 5000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 4000, spellID: 200, sourceID: 5)

        let result = normalizer.normalize(playerCasts: [player], bossCasts: [boss], windowSeconds: 30)

        XCTAssertTrue(result.isEmpty)
    }

    func test_playerCastAtWindowBoundary_included() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 30_000, spellID: 200, sourceID: 5)  // 정확히 30초

        let result = normalizer.normalize(playerCasts: [player], bossCasts: [boss], windowSeconds: 30)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].delay, 30.0, accuracy: 0.001)
    }

    func test_multipleBossCasts_eachMatchesSeparately() {
        let boss1 = CastEvent(timestamp: 1000, spellID: 100, sourceID: 1)
        let boss2 = CastEvent(timestamp: 50_000, spellID: 101, sourceID: 1)
        let player1 = CastEvent(timestamp: 2000, spellID: 200, sourceID: 5)
        let player2 = CastEvent(timestamp: 51_000, spellID: 201, sourceID: 5)

        let result = normalizer.normalize(playerCasts: [player1, player2], bossCasts: [boss1, boss2], windowSeconds: 30)

        XCTAssertEqual(result.count, 2)
    }

    func test_sameBossSpell_multipleOccurrences_allRecorded() {
        let boss1 = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let boss2 = CastEvent(timestamp: 60_000, spellID: 100, sourceID: 1)
        let player1 = CastEvent(timestamp: 1000, spellID: 200, sourceID: 5)
        let player2 = CastEvent(timestamp: 61_000, spellID: 201, sourceID: 5)

        let result = normalizer.normalize(playerCasts: [player1, player2], bossCasts: [boss1, boss2], windowSeconds: 30)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].bossSpellID, 100)
        XCTAssertEqual(result[1].bossSpellID, 100)
    }

    func test_delayCalculation_millisecondPrecision() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 2500, spellID: 200, sourceID: 5)

        let result = normalizer.normalize(playerCasts: [player], bossCasts: [boss], windowSeconds: 30)

        XCTAssertEqual(result[0].delay, 2.5, accuracy: 0.001)
    }
}
