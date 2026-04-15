final class MockLuaGenerator: LuaGenerating {
    var result: LuaOutput = LuaOutput(luaText: "-- mock lua", entryCount: 0)

    func generate(entries: [TimelineEntry], spec: HealerSpec, encounterID: Int) -> LuaOutput {
        result
    }
}
