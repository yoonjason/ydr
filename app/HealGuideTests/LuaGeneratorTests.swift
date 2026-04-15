import XCTest
@testable import HealGuide

final class LuaGeneratorTests: XCTestCase {
    private let generator = LuaGenerator()

    func test_emptyEntries_generatesEmptyTable() {
        let output = generator.generate(entries: [], spec: .discPriest, encounterID: 2599)

        XCTAssertEqual(output.entryCount, 0)
        XCTAssertTrue(output.luaText.contains("HGPT_Data[\"DiscPriest\"]"))
        XCTAssertTrue(output.luaText.contains("HGPT_Data[\"DiscPriest\"][2599] = {"))
    }

    func test_singleEntry_generatesCorrectLua() {
        let entry = TimelineEntry(bossSpellID: 100, playerSpellID: 200, delay: 2.5)
        let output = generator.generate(entries: [entry], spec: .discPriest, encounterID: 2599)

        XCTAssertEqual(output.entryCount, 1)
        XCTAssertTrue(output.luaText.contains("[100] = {"))
        XCTAssertTrue(output.luaText.contains("{ spellID = 200, delay = 2.5 }"))
    }

    func test_multipleEntriesSameBossSpell_groupedTogether() {
        let entries = [
            TimelineEntry(bossSpellID: 100, playerSpellID: 200, delay: 1.0),
            TimelineEntry(bossSpellID: 100, playerSpellID: 201, delay: 5.0)
        ]
        let output = generator.generate(entries: entries, spec: .discPriest, encounterID: 2599)

        XCTAssertEqual(output.entryCount, 2)
        let occurrences = output.luaText.components(separatedBy: "[100] = {").count - 1
        XCTAssertEqual(occurrences, 1)  // 단 한 번만 등장해야 함
    }

    func test_multipleBossSpells_sortedByID() {
        let entries = [
            TimelineEntry(bossSpellID: 300, playerSpellID: 200, delay: 1.0),
            TimelineEntry(bossSpellID: 100, playerSpellID: 201, delay: 2.0)
        ]
        let output = generator.generate(entries: entries, spec: .discPriest, encounterID: 2599)

        let pos100 = output.luaText.range(of: "[100] = {")!.lowerBound
        let pos300 = output.luaText.range(of: "[300] = {")!.lowerBound
        XCTAssertLessThan(pos100, pos300)
    }

    func test_specKey_usedCorrectly() {
        let output = generator.generate(entries: [], spec: .restoShaman, encounterID: 3000)

        XCTAssertTrue(output.luaText.contains("HGPT_Data[\"RestoShaman\"]"))
    }

    func test_delayFormatting_oneDecimalPlace() {
        let entry = TimelineEntry(bossSpellID: 100, playerSpellID: 200, delay: 3.0)
        let output = generator.generate(entries: [entry], spec: .discPriest, encounterID: 2599)

        XCTAssertTrue(output.luaText.contains("delay = 3.0"))
    }

    func test_entryCount_matchesInputCount() {
        let entries = (1...5).map { i in
            TimelineEntry(bossSpellID: 100, playerSpellID: 200 + i, delay: Double(i))
        }
        let output = generator.generate(entries: entries, spec: .discPriest, encounterID: 2599)

        XCTAssertEqual(output.entryCount, 5)
    }

    func test_initializerGuard_includesOrStatement() {
        let output = generator.generate(entries: [], spec: .holyPriest, encounterID: 1000)

        XCTAssertTrue(output.luaText.contains("HGPT_Data[\"HolyPriest\"] = HGPT_Data[\"HolyPriest\"] or {}"))
    }
}
