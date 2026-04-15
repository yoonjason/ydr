struct BossWindow: Equatable {
    let encounterID: Int
    let name: String
    let startTime: Int64
    let endTime: Int64
}

struct AbsoluteEntry: Equatable {
    let spellID: Int
    let offset: Double
}

struct ReactionEntry: Equatable {
    let bossAbilityID: Int
    let playerSpellID: Int
    let delay: Double
}

struct EncounterBlock: Equatable {
    let encounterID: Int
    let name: String
    let duration: Double
    let absolute: [AbsoluteEntry]
    let reactions: [ReactionEntry]
}
