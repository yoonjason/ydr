import Foundation

struct DiscoveredSpell: Identifiable, Equatable {
    let id: Int
    var name: String
    var selected: Bool

    init(spellID: Int, name: String, selected: Bool = true) {
        self.id = spellID
        self.name = name
        self.selected = selected
    }
}
