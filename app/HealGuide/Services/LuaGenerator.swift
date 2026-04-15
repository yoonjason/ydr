struct LuaGenerator: LuaGenerating {
    func generate(entries: [TimelineEntry], spec: HealerSpec, encounterID: Int) -> LuaOutput {
        var grouped: [Int: [TimelineEntry]] = [:]
        for entry in entries {
            grouped[entry.bossSpellID, default: []].append(entry)
        }

        let specKey = spec.rawValue
        var lines: [String] = []
        lines.append("HGPT_Data[\"\(specKey)\"] = HGPT_Data[\"\(specKey)\"] or {}")
        lines.append("HGPT_Data[\"\(specKey)\"][\(encounterID)] = {")

        for bossSpellID in grouped.keys.sorted() {
            lines.append("  [\(bossSpellID)] = {")
            for entry in grouped[bossSpellID]! {
                let delayStr = String(format: "%.1f", entry.delay)
                lines.append("    { spellID = \(entry.playerSpellID), delay = \(delayStr) },")
            }
            lines.append("  },")
        }

        lines.append("}")

        return LuaOutput(luaText: lines.joined(separator: "\n"), entryCount: entries.count)
    }
}
