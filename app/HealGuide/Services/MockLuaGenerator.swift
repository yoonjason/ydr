final class MockLuaGenerator: LuaGenerating {
    var result: String = "-- mock lua"

    func generate(blocks: [EncounterBlock], metadata: ExportMetadata) -> String {
        result
    }
}
