struct SpellResolver: SpellResolving {
    private let store: SpellCatalogStoring

    init(store: SpellCatalogStoring) {
        self.store = store
    }

    func spells(for spec: HealerSpec) -> [SpellEntry] {
        let ids = SpecSpellCatalog.spellIDs(for: spec)
        let catalog = store.loadAll()
        return ids.map { id in
            if let record = catalog[id] {
                return SpellEntry(id: id, nameKR: record.nameKR, nameEN: record.nameEN, iconURL: record.iconURL)
            }
            return SpellEntry(id: id, nameKR: "Spell #\(id)", nameEN: "Spell #\(id)")
        }
    }

    func allSpellIDs(for spec: HealerSpec) -> [Int] {
        SpecSpellCatalog.spellIDs(for: spec)
    }
}
