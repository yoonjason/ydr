import XCTest
@testable import HealGuide

final class LuaGeneratorTests: XCTestCase {
    private let generator = LuaGenerator()
    private let metadata = ExportMetadata(spec: .discPriest)

    private func makeBlock(
        encounterID: Int = 2599,
        name: String = "Ulgrax",
        duration: Double = 180.0,
        absolute: [AbsoluteEntry] = [],
        reactions: [ReactionEntry] = []
    ) -> EncounterBlock {
        EncounterBlock(encounterID: encounterID, name: name, duration: duration, absolute: absolute, reactions: reactions)
    }

    // MARK: - 기본 구조

    func test_emptyBlocks_generatesInitializerOnly() {
        let output = generator.generate(blocks: [], metadata: metadata)
        XCTAssertTrue(output.contains("HGPT_Data[\"DiscPriest\"] = HGPT_Data[\"DiscPriest\"] or {}"))
        XCTAssertFalse(output.contains("encounterID"))
    }

    func test_singleBlock_containsNameAndDuration() {
        let block = makeBlock(name: "Ulgrax", duration: 180.5)
        let output = generator.generate(blocks: [block], metadata: metadata)

        XCTAssertTrue(output.contains("name = \"Ulgrax\","))
        XCTAssertTrue(output.contains("duration = 180.5,"))
    }

    func test_specKey_usedCorrectly() {
        let output = generator.generate(
            blocks: [makeBlock()],
            metadata: ExportMetadata(spec: .restoShaman)
        )
        XCTAssertTrue(output.contains("HGPT_Data[\"RestoShaman\"]"))
    }

    func test_encounterID_inKey() {
        let block = makeBlock(encounterID: 2599)
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("HGPT_Data[\"DiscPriest\"][2599] = {"))
    }

    // MARK: - timeline (absolute)

    func test_emptyAbsolute_timelineSectionPresent() {
        let block = makeBlock(absolute: [])
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("timeline = {"))
    }

    func test_absoluteEntry_generatesCorrectLine() {
        let entry = AbsoluteEntry(spellID: 17, offset: 3.2)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("{ spellID = 17, offset = 3.2 },"))
    }

    func test_offsetFormatting_oneDecimalPlace() {
        let entry = AbsoluteEntry(spellID: 17, offset: 5.0)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("offset = 5.0"))
    }

    // MARK: - reactions

    func test_emptyReactions_reactionsSectionPresent() {
        let block = makeBlock(reactions: [])
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("reactions = {"))
    }

    func test_reactionEntry_generatesCorrectLine() {
        let reaction = ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 0.5)
        let block = makeBlock(reactions: [reaction])
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("[100] = {"))
        XCTAssertTrue(output.contains("{ spellID = 17, delay = 0.5 },"))
    }

    func test_multipleReactionsSameBossSpell_groupedTogether() {
        let reactions = [
            ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 1.0),
            ReactionEntry(bossAbilityID: 100, playerSpellID: 18, delay: 2.0)
        ]
        let block = makeBlock(reactions: reactions)
        let output = generator.generate(blocks: [block], metadata: metadata)
        let occurrences = output.components(separatedBy: "[100] = {").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func test_multipleBossSpellsSortedByID() {
        let reactions = [
            ReactionEntry(bossAbilityID: 300, playerSpellID: 17, delay: 1.0),
            ReactionEntry(bossAbilityID: 100, playerSpellID: 18, delay: 2.0)
        ]
        let block = makeBlock(reactions: reactions)
        let output = generator.generate(blocks: [block], metadata: metadata)
        let pos100 = output.range(of: "[100] = {")!.lowerBound
        let pos300 = output.range(of: "[300] = {")!.lowerBound
        XCTAssertLessThan(pos100, pos300)
    }

    func test_delayFormatting_oneDecimalPlace() {
        let reaction = ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 3.0)
        let block = makeBlock(reactions: [reaction])
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("delay = 3.0"))
    }

    // MARK: - name 이스케이프

    func test_nameWithDoubleQuote_isEscaped() {
        let block = makeBlock(name: "Boss\"Name")
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("name = \"Boss\\\"Name\","))
    }

    func test_nameWithBackslash_isEscaped() {
        let block = makeBlock(name: "Boss\\Name")
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("name = \"Boss\\\\Name\","))
    }

    func test_nameWithBothSpecialChars_isEscaped() {
        let block = makeBlock(name: "Bos\\\"s")
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("name = \"Bos\\\\\\\"s\","))
    }

    // MARK: - 멀티 블록

    func test_multipleBlocks_allEncounterIDsPresent() {
        let block1 = makeBlock(encounterID: 2599, name: "Boss A")
        let block2 = makeBlock(encounterID: 2600, name: "Boss B")
        let output = generator.generate(blocks: [block1, block2], metadata: metadata)
        XCTAssertTrue(output.contains("HGPT_Data[\"DiscPriest\"][2599] = {"))
        XCTAssertTrue(output.contains("HGPT_Data[\"DiscPriest\"][2600] = {"))
    }

    func test_multipleBlocks_initializerAppearsOnce() {
        let block1 = makeBlock(encounterID: 2599)
        let block2 = makeBlock(encounterID: 2600)
        let output = generator.generate(blocks: [block1, block2], metadata: metadata)
        let count = output.components(separatedBy: "HGPT_Data[\"DiscPriest\"] = HGPT_Data").count - 1
        XCTAssertEqual(count, 1)
    }

    // MARK: - 혼합 (absolute + reactions)

    func test_blockWithBothSections_allPresent() {
        let block = makeBlock(
            absolute: [AbsoluteEntry(spellID: 17, offset: 3.2)],
            reactions: [ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 0.5)]
        )
        let output = generator.generate(blocks: [block], metadata: metadata)
        XCTAssertTrue(output.contains("timeline = {"))
        XCTAssertTrue(output.contains("reactions = {"))
        XCTAssertTrue(output.contains("offset = 3.2"))
        XCTAssertTrue(output.contains("delay = 0.5"))
    }
}
