final class MockSpellResolver: SpellResolving {
    var spellsResult: [SpellEntry] = []

    func spells(for spec: HealerSpec) -> [SpellEntry] {
        spellsResult.isEmpty
            ? SpecSpellCatalog.spellIDs(for: spec).map { SpellEntry(id: $0, nameKR: "Spell #\($0)", nameEN: "Spell #\($0)") }
            : spellsResult
    }

    func allSpellIDs(for spec: HealerSpec) -> [Int] {
        SpecSpellCatalog.spellIDs(for: spec)
    }
}
