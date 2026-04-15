protocol LuaGenerating {
    func generate(entries: [TimelineEntry], spec: HealerSpec, encounterID: Int) -> LuaOutput
}
