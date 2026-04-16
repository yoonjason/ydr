struct SpellEntry: Equatable, Hashable, Identifiable {
    let id: Int
    let nameKR: String
    let nameEN: String
    let iconURL: String?

    init(id: Int, nameKR: String, nameEN: String, iconURL: String? = nil) {
        self.id = id
        self.nameKR = nameKR
        self.nameEN = nameEN
        self.iconURL = iconURL
    }
}
