protocol LuaGenerating {
    func generate(blocks: [EncounterBlock], metadata: ExportMetadata) -> String
}
