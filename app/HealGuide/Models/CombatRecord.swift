import Foundation

struct CombatRecord: Equatable, Identifiable {
    let id: UUID
    let encounterID: Int
    let timestamp: Date
    let duration: Double
    let stats: CombatStats
    let events: [CombatEvent]

    init(encounterID: Int, timestamp: Date, duration: Double, stats: CombatStats, events: [CombatEvent]) {
        self.id = UUID()
        self.encounterID = encounterID
        self.timestamp = timestamp
        self.duration = duration
        self.stats = stats
        self.events = events
    }
}

struct CombatStats: Equatable {
    let fired: Int
    let conditionSkipped: Int
    let cooldownSkipped: Int
    let used: Int

    var accuracy: Double {
        guard fired > 0 else { return 0 }
        return Double(used) / Double(fired)
    }
}

struct CombatEvent: Equatable {
    let type: String
    let spellID: Int
    let timestamp: Double
    let source: String?
}
