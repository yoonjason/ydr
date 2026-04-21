import Foundation

struct ExportMetadata: Equatable {
    let spec: HealerSpec
    let dungeonName: String
    let sourceURL: String
    let generatedAt: Date
    var bossSpellNames: [Int: String] = [:]
    // encounterID → 전술 요약. LuaGenerator 가 tactics 블록 생성에 사용.
    var tacticsByEncounter: [Int: EncounterTacticsSummary] = [:]
}

struct LuaOutput: Equatable {
    let blocks: [EncounterBlock]
    let luaText: String
    var bossNameMap: [Int: String] = [:]

    var blockCount: Int { blocks.count }
    var timelineCount: Int { blocks.reduce(0) { $0 + $1.absolute.count } }
    var reactionCount: Int { blocks.reduce(0) { $0 + $1.reactions.count } }
}
