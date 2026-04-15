import XCTest
@testable import HealGuide

final class TimelineNormalizerTests: XCTestCase {
    private let normalizer = TimelineNormalizer()

    // MARK: - absolute

    func test_absolute_empty_whenNoBossCasts() {
        let (absolute, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [], playerCasts: [], maxWindow: 30
        )
        XCTAssertTrue(absolute.isEmpty)
    }

    func test_absolute_offsetRelativeToEncounterStart() {
        let boss = CastEvent(timestamp: 5_000, spellID: 100, sourceID: 1)
        let (absolute, _) = normalizer.normalize(
            encounterStart: 2_000, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [], maxWindow: 30
        )
        XCTAssertEqual(absolute.count, 1)
        XCTAssertEqual(absolute[0].spellID, 100)
        XCTAssertEqual(absolute[0].offset, 3.0, accuracy: 0.001)
    }

    func test_absolute_multipleBossCasts_allIncluded() {
        let casts = [
            CastEvent(timestamp: 0, spellID: 100, sourceID: 1),
            CastEvent(timestamp: 10_000, spellID: 101, sourceID: 1),
            CastEvent(timestamp: 20_500, spellID: 102, sourceID: 1)
        ]
        let (absolute, _) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: casts, playerCasts: [], maxWindow: 30
        )
        XCTAssertEqual(absolute.count, 3)
        XCTAssertEqual(absolute[2].offset, 20.5, accuracy: 0.001)
    }

    // MARK: - reactions

    func test_reactions_empty_whenNoPlayerCasts() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let (_, reactions) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [], maxWindow: 30
        )
        XCTAssertTrue(reactions.isEmpty)
    }

    func test_reactions_playerWithinWindow_included() {
        let boss = CastEvent(timestamp: 1_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 3_000, spellID: 200, sourceID: 5)
        let (_, reactions) = normalizer.normalize(
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
        let (_, reactions) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertTrue(reactions.isEmpty)
    }

    func test_reactions_playerBeforeBoss_excluded() {
        let boss = CastEvent(timestamp: 5_000, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 4_000, spellID: 200, sourceID: 5)
        let (_, reactions) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertTrue(reactions.isEmpty)
    }

    func test_reactions_playerAtWindowBoundary_included() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 30_000, spellID: 200, sourceID: 5)
        let (_, reactions) = normalizer.normalize(
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

        let (_, reactions) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss1, boss2], playerCasts: [player1, player2], maxWindow: 30
        )
        XCTAssertEqual(reactions.count, 2)
    }

    func test_reactions_delayMillisecondPrecision() {
        let boss = CastEvent(timestamp: 0, spellID: 100, sourceID: 1)
        let player = CastEvent(timestamp: 2_500, spellID: 200, sourceID: 5)
        let (_, reactions) = normalizer.normalize(
            encounterStart: 0, encounterEnd: 60_000,
            bossCasts: [boss], playerCasts: [player], maxWindow: 30
        )
        XCTAssertEqual(reactions[0].delay, 2.5, accuracy: 0.001)
    }
}
