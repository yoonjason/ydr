protocol SpellResolving {
    func spells(for spec: HealerSpec) -> [SpellEntry]
    func allSpellIDs(for spec: HealerSpec) -> [Int]
}
