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

struct LeadInEntry: Equatable {
    let bossAbilityID: Int
    let playerSpellID: Int
    let offset: Double  // 음수: 보스 캐스트 기준 몇 초 전 (예: -12.0 = 12초 전)
}

struct EncounterBlock: Equatable {
    let encounterID: Int
    let name: String
    let duration: Double
    let absolute: [AbsoluteEntry]
    let reactions: [ReactionEntry]
    let leadIns: [LeadInEntry]
}
