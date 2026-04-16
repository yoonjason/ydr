import Foundation

struct ExportMetadata: Equatable {
    let spec: HealerSpec
    let dungeonName: String
    let sourceURL: String
    let generatedAt: Date
    var bossSpellNames: [Int: String] = [:]
}

struct LuaOutput: Equatable {
    let blocks: [EncounterBlock]
    let luaText: String
    var bossNameMap: [Int: String] = [:]

    var blockCount: Int { blocks.count }
    var timelineCount: Int { blocks.reduce(0) { $0 + $1.absolute.count } }
    var reactionCount: Int { blocks.reduce(0) { $0 + $1.reactions.count } }
}
