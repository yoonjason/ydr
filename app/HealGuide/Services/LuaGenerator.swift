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
                if let condition = entry.condition {
                    let conditionLine = conditionLua(condition, indent: "          ")
                    lines.append("        { spellID = \(entry.spellID), offset = \(offsetStr),")
                    lines.append("          condition = \(conditionLine),")
                    lines.append("        },")
                } else {
                    lines.append("        { spellID = \(entry.spellID), offset = \(offsetStr) },")
                }
            }
            lines.append("      },")
            lines.append("      reactions = {")
            var grouped: [Int: [ReactionEntry]] = [:]
            for reaction in block.reactions {
                grouped[reaction.bossAbilityID, default: []].append(reaction)
            }
            let bossNames = metadata.bossSpellNames
            for bossID in grouped.keys.sorted() {
                let nameComment = bossNames[bossID].map { " -- \($0)" } ?? ""
                lines.append("        [\(bossID)] = {\(nameComment)")
                for reaction in grouped[bossID, default: []] {
                    let delayStr = String(format: "%.1f", reaction.delay)
                    if let condition = reaction.condition {
                        let conditionLine = conditionLua(condition, indent: "            ")
                        lines.append("          { spellID = \(reaction.playerSpellID), delay = \(delayStr),")
                        lines.append("            condition = \(conditionLine),")
                        lines.append("          },")
                    } else {
                        lines.append("          { spellID = \(reaction.playerSpellID), delay = \(delayStr) },")
                    }
                }
                lines.append("        },")
            }
            lines.append("      },")
            lines.append("      leadIns = {")
            var leadGrouped: [Int: [LeadInEntry]] = [:]
            for lead in block.leadIns {
                leadGrouped[lead.bossAbilityID, default: []].append(lead)
            }
            for bossID in leadGrouped.keys.sorted() {
                let nameComment = bossNames[bossID].map { " -- \($0)" } ?? ""
                lines.append("        [\(bossID)] = {\(nameComment)")
                for lead in leadGrouped[bossID, default: []] {
                    let offsetStr = String(format: "%.1f", lead.offset)
                    if let condition = lead.condition {
                        let conditionLine = conditionLua(condition, indent: "            ")
                        lines.append("          { spellID = \(lead.playerSpellID), offset = \(offsetStr),")
                        lines.append("            condition = \(conditionLine),")
                        lines.append("          },")
                    } else {
                        lines.append("          { spellID = \(lead.playerSpellID), offset = \(offsetStr) },")
                    }
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

    private func conditionLua(_ node: ConditionNode, indent: String) -> String {
        switch node.op {
        case "and", "or":
            let inner = indent + "  "
            let operandLines = (node.operands ?? []).map { inner + conditionLua($0, indent: inner) }
            return "{ op = \"\(node.op)\", operands = {\n"
                + operandLines.joined(separator: ",\n")
                + ",\n" + indent + "} }"
        case "not":
            let innerNode = node.operands?.first.map { conditionLua($0, indent: indent + "  ") } ?? "nil"
            return "{ op = \"not\", operands = { \(innerNode) } }"
        default:
            let valueStr = node.value.map { String(format: "%g", $0) } ?? "nil"
            let fieldStr = node.field ?? ""
            if let spellID = node.spellID {
                return "{ op = \"\(node.op)\", field = \"\(fieldStr)\", spellID = \(spellID), value = \(valueStr) }"
            }
            return "{ op = \"\(node.op)\", field = \"\(fieldStr)\", value = \(valueStr) }"
        }
    }

    private func escapeLuaString(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
