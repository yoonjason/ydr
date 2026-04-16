struct BossWindow: Equatable {
    let encounterID: Int
    let name: String
    let startTime: Int64
    let endTime: Int64
}

struct ConditionNode: Equatable {
    let op: String
    let field: String?
    let value: Double?
    let spellID: Int?
    let operands: [ConditionNode]?

    init(
        op: String,
        field: String? = nil,
        value: Double? = nil,
        spellID: Int? = nil,
        operands: [ConditionNode]? = nil
    ) {
        self.op = op
        self.field = field
        self.value = value
        self.spellID = spellID
        self.operands = operands
    }
}

struct AbsoluteEntry: Equatable {
    let spellID: Int
    let offset: Double
    let condition: ConditionNode?

    init(spellID: Int, offset: Double, condition: ConditionNode? = nil) {
        self.spellID = spellID
        self.offset = offset
        self.condition = condition
    }
}

struct ReactionEntry: Equatable {
    let bossAbilityID: Int
    let playerSpellID: Int
    let delay: Double
    let condition: ConditionNode?

    init(bossAbilityID: Int, playerSpellID: Int, delay: Double, condition: ConditionNode? = nil) {
        self.bossAbilityID = bossAbilityID
        self.playerSpellID = playerSpellID
        self.delay = delay
        self.condition = condition
    }
}

struct LeadInEntry: Equatable {
    let bossAbilityID: Int
    let playerSpellID: Int
    let offset: Double
    let condition: ConditionNode?

    init(bossAbilityID: Int, playerSpellID: Int, offset: Double, condition: ConditionNode? = nil) {
        self.bossAbilityID = bossAbilityID
        self.playerSpellID = playerSpellID
        self.offset = offset
        self.condition = condition
    }
}

struct EncounterBlock: Equatable {
    let encounterID: Int
    let name: String
    let duration: Double
    let absolute: [AbsoluteEntry]
    let reactions: [ReactionEntry]
    let leadIns: [LeadInEntry]
}
