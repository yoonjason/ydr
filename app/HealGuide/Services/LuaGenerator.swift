import Foundation

struct LuaGenerator: LuaGenerating {
    func generate(blocks: [EncounterBlock], metadata: ExportMetadata) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        let generatedAt = formatter.string(from: metadata.generatedAt)

        var lines: [String] = []
        lines.append("return {")
        lines.append("  version = 1,")
        lines.append("  dungeonName = \"\(escapeLuaString(metadata.dungeonName))\",")
        lines.append("  spec = \"\(metadata.spec.rawValue)\",")
        lines.append("  generatedAt = \"\(generatedAt)\",")
        lines.append("  sourceURL = \"\(escapeLuaString(metadata.sourceURL))\",")
        lines.append("  bosses = {")

        for block in blocks {
            let durationStr = String(format: "%.1f", block.duration)
            lines.append("    [\(block.encounterID)] = {")
            lines.append("      name = \"\(escapeLuaString(block.name))\",")
            lines.append("      duration = \(durationStr),")
            lines.append("      timeline = {")
            for entry in block.absolute {
                let offsetStr = String(format: "%.1f", entry.offset)
                lines.append("        { spellID = \(entry.spellID), offset = \(offsetStr) },")
            }
            lines.append("      },")
            lines.append("      reactions = {")
            var grouped: [Int: [ReactionEntry]] = [:]
            for reaction in block.reactions {
                grouped[reaction.bossAbilityID, default: []].append(reaction)
            }
            for bossID in grouped.keys.sorted() {
                lines.append("        [\(bossID)] = {")
                for reaction in grouped[bossID, default: []] {
                    let delayStr = String(format: "%.1f", reaction.delay)
                    lines.append("          { spellID = \(reaction.playerSpellID), delay = \(delayStr) },")
                }
                lines.append("        },")
            }
            lines.append("      },")
            lines.append("    },")
        }

        lines.append("  },")
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private func escapeLuaString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
