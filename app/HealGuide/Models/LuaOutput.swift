struct ExportMetadata: Equatable {
    let spec: HealerSpec
    // 향후 reportURL/generatedAt 추가 가능
}

struct LuaOutput: Equatable {
    let blocks: [EncounterBlock]
    let luaText: String

    var blockCount: Int { blocks.count }
    var timelineCount: Int { blocks.reduce(0) { $0 + $1.absolute.count } }
    var reactionCount: Int { blocks.reduce(0) { $0 + $1.reactions.count } }
}
