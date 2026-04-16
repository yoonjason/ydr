import XCTest
@testable import HealGuide

final class LuaGeneratorTests: XCTestCase {
    private let generator = LuaGenerator()
    private let fixedDate = Date(timeIntervalSince1970: 0)

    private func makeMetadata(
        spec: HealerSpec = .discPriest,
        dungeonName: String = "The Stonevault",
        sourceURL: String = "https://www.warcraftlogs.com/reports/abc123#fight=1",
        generatedAt: Date? = nil
    ) -> ExportMetadata {
        ExportMetadata(
            spec: spec,
            dungeonName: dungeonName,
            sourceURL: sourceURL,
            generatedAt: generatedAt ?? fixedDate
        )
    }

    private func makeBlock(
        encounterID: Int = 3056,
        name: String = "Emberdawn",
        duration: Double = 180.0,
        absolute: [AbsoluteEntry] = [],
        reactions: [ReactionEntry] = [],
        leadIns: [LeadInEntry] = []
    ) -> EncounterBlock {
        EncounterBlock(
            encounterID: encounterID,
            name: name,
            duration: duration,
            absolute: absolute,
            reactions: reactions,
            leadIns: leadIns
        )
    }

    // MARK: - 최상위 구조

    func test_output_startsWithReturn() {
        let output = generator.generate(blocks: [], metadata: makeMetadata())
        XCTAssertTrue(output.hasPrefix("return {"))
    }

    func test_output_containsVersion1() {
        let output = generator.generate(blocks: [], metadata: makeMetadata())
        XCTAssertTrue(output.contains("version = 1,"))
    }

    func test_output_containsDungeonName() {
        let output = generator.generate(blocks: [], metadata: makeMetadata(dungeonName: "The Stonevault"))
        XCTAssertTrue(output.contains("dungeonName = \"The Stonevault\","))
    }

    func test_output_containsSpec() {
        let output = generator.generate(blocks: [], metadata: makeMetadata(spec: .restoShaman))
        XCTAssertTrue(output.contains("spec = \"RestoShaman\","))
    }

    func test_output_containsGeneratedAt_iso8601UTC() {
        let output = generator.generate(blocks: [], metadata: makeMetadata(generatedAt: fixedDate))
        XCTAssertTrue(output.contains("generatedAt = \"1970-01-01T00:00:00Z\","))
    }

    func test_output_containsSourceURL() {
        let url = "https://www.warcraftlogs.com/reports/abc#fight=1"
        let output = generator.generate(blocks: [], metadata: makeMetadata(sourceURL: url))
        XCTAssertTrue(output.contains("sourceURL = \"\(url)\","))
    }

    func test_output_containsBossesTable() {
        let output = generator.generate(blocks: [], metadata: makeMetadata())
        XCTAssertTrue(output.contains("bosses = {"))
    }

    func test_emptyBlocks_noBossEntries() {
        let output = generator.generate(blocks: [], metadata: makeMetadata())
        XCTAssertFalse(output.contains("encounterID"))
        XCTAssertFalse(output.contains("duration"))
    }

    // MARK: - 보스 테이블

    func test_singleBlock_containsEncounterIDKey() {
        let block = makeBlock(encounterID: 3056)
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("[3056] = {"))
    }

    func test_singleBlock_containsNameAndDuration() {
        let block = makeBlock(name: "Emberdawn", duration: 180.5)
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("name = \"Emberdawn\","))
        XCTAssertTrue(output.contains("duration = 180.5,"))
    }

    // MARK: - timeline

    func test_emptyAbsolute_timelineSectionPresent() {
        let block = makeBlock(absolute: [])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("timeline = {"))
    }

    func test_absoluteEntry_generatesCorrectLine() {
        let entry = AbsoluteEntry(spellID: 17, offset: 3.2)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("{ spellID = 17, offset = 3.2 },"))
    }

    func test_offsetFormatting_oneDecimalPlace() {
        let entry = AbsoluteEntry(spellID: 17, offset: 5.0)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("offset = 5.0"))
    }

    // MARK: - reactions

    func test_emptyReactions_reactionsSectionPresent() {
        let block = makeBlock(reactions: [])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("reactions = {"))
    }

    func test_reactionEntry_generatesCorrectLine() {
        let reaction = ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 0.5)
        let block = makeBlock(reactions: [reaction])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("[100] = {"))
        XCTAssertTrue(output.contains("{ spellID = 17, delay = 0.5 },"))
    }

    func test_multipleReactionsSameBossSpell_groupedTogether() {
        let reactions = [
            ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 1.0),
            ReactionEntry(bossAbilityID: 100, playerSpellID: 18, delay: 2.0)
        ]
        let block = makeBlock(reactions: reactions)
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        let occurrences = output.components(separatedBy: "[100] = {").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func test_multipleBossSpellsSortedByID() {
        let reactions = [
            ReactionEntry(bossAbilityID: 300, playerSpellID: 17, delay: 1.0),
            ReactionEntry(bossAbilityID: 100, playerSpellID: 18, delay: 2.0)
        ]
        let block = makeBlock(reactions: reactions)
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        let pos100 = output.range(of: "[100] = {")!.lowerBound
        let pos300 = output.range(of: "[300] = {")!.lowerBound
        XCTAssertLessThan(pos100, pos300)
    }

    func test_delayFormatting_oneDecimalPlace() {
        let reaction = ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 3.0)
        let block = makeBlock(reactions: [reaction])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("delay = 3.0"))
    }

    // MARK: - 이스케이프

    func test_dungeonName_doubleQuoteEscaped() {
        let output = generator.generate(blocks: [], metadata: makeMetadata(dungeonName: "The \"Vault\""))
        XCTAssertTrue(output.contains("dungeonName = \"The \\\"Vault\\\"\","))
    }

    func test_bossName_doubleQuoteEscaped() {
        let block = makeBlock(name: "Boss\"Name")
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("name = \"Boss\\\"Name\","))
    }

    func test_bossName_backslashEscaped() {
        let block = makeBlock(name: "Boss\\Name")
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("name = \"Boss\\\\Name\","))
    }

    func test_sourceURL_backslashEscaped() {
        let output = generator.generate(blocks: [], metadata: makeMetadata(sourceURL: "url\\path"))
        XCTAssertTrue(output.contains("sourceURL = \"url\\\\path\","))
    }

    // MARK: - 멀티 보스

    func test_multipleBlocks_allEncounterIDsPresent() {
        let block1 = makeBlock(encounterID: 3056, name: "Boss A")
        let block2 = makeBlock(encounterID: 3057, name: "Boss B")
        let output = generator.generate(blocks: [block1, block2], metadata: makeMetadata())
        XCTAssertTrue(output.contains("[3056] = {"))
        XCTAssertTrue(output.contains("[3057] = {"))
    }

    func test_multipleBlocks_noDuplicateBossesKey() {
        let block1 = makeBlock(encounterID: 3056)
        let block2 = makeBlock(encounterID: 3057)
        let output = generator.generate(blocks: [block1, block2], metadata: makeMetadata())
        let count = output.components(separatedBy: "bosses = {").count - 1
        XCTAssertEqual(count, 1)
    }

    // MARK: - 혼합 (timeline + reactions)

    func test_blockWithBothSections_allPresent() {
        let block = makeBlock(
            absolute: [AbsoluteEntry(spellID: 17, offset: 3.2)],
            reactions: [ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 0.5)]
        )
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("timeline = {"))
        XCTAssertTrue(output.contains("reactions = {"))
        XCTAssertTrue(output.contains("offset = 3.2"))
        XCTAssertTrue(output.contains("delay = 0.5"))
    }

    // MARK: - condition 출력

    func test_absoluteEntry_nilCondition_backwardCompatibleFormat() {
        let entry = AbsoluteEntry(spellID: 17, offset: 3.2)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("{ spellID = 17, offset = 3.2 },"))
        XCTAssertFalse(output.contains("condition"))
    }

    func test_absoluteEntry_simpleLeafCondition() {
        let condition = ConditionNode(op: "lt", field: "partyHPAvg", value: 0.6)
        let entry = AbsoluteEntry(spellID: 17, offset: 3.2, condition: condition)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("{ op = \"lt\", field = \"partyHPAvg\", value = 0.6 }"))
    }

    func test_reactionEntry_leafConditionWithSpellID() {
        let condition = ConditionNode(op: "eq", field: "spellOnCooldown", value: 1, spellID: 65116)
        let reaction = ReactionEntry(bossAbilityID: 100, playerSpellID: 17, delay: 0.5, condition: condition)
        let block = makeBlock(reactions: [reaction])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("{ op = \"eq\", field = \"spellOnCooldown\", spellID = 65116, value = 1 }"))
    }

    func test_leadInEntry_andCompoundCondition() {
        let condition = ConditionNode(op: "and", operands: [
            ConditionNode(op: "lt", field: "partyHPAvg", value: 0.6),
            ConditionNode(op: "gt", field: "playerMana", value: 0.3)
        ])
        let lead = LeadInEntry(bossAbilityID: 100, playerSpellID: 17, offset: -8.0, condition: condition)
        let block = makeBlock(leadIns: [lead])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("op = \"and\", operands = {"))
        XCTAssertTrue(output.contains("{ op = \"lt\", field = \"partyHPAvg\", value = 0.6 }"))
        XCTAssertTrue(output.contains("{ op = \"gt\", field = \"playerMana\", value = 0.3 }"))
    }

    func test_notCondition_wrapsInnerLeaf() {
        let condition = ConditionNode(op: "not", operands: [
            ConditionNode(op: "eq", field: "spellOnCooldown", value: 1, spellID: 65116)
        ])
        let entry = AbsoluteEntry(spellID: 17, offset: 3.2, condition: condition)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        XCTAssertTrue(output.contains("op = \"not\", operands = {"))
        XCTAssertTrue(output.contains("spellID = 65116"))
    }

    func test_compoundCondition_noDoubleIndent() {
        let condition = ConditionNode(op: "and", operands: [
            ConditionNode(op: "lt", field: "partyHPAvg", value: 0.6)
        ])
        let entry = AbsoluteEntry(spellID: 17, offset: 3.2, condition: condition)
        let block = makeBlock(absolute: [entry])
        let output = generator.generate(blocks: [block], metadata: makeMetadata())
        // 이중 indent 회귀 방지: 내부 리프가 정확히 12칸 들여쓰기로 시작해야 함
        // (condition 시작 indent 10칸 + inner 2칸 = 12칸)
        XCTAssertTrue(output.contains("            { op = \"lt\", field = \"partyHPAvg\", value = 0.6 }"))
        XCTAssertFalse(output.contains("              { op = \"lt\""))
    }
}
