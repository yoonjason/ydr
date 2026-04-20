import Foundation

struct RankerLuaSerializer {
    /// HGPT_RankerData.lua 파일 내용 생성 (Option B: entries 배열 래퍼)
    func serialize(_ entries: [HGPTRankerData]) -> String {
        var lines: [String] = []
        lines.append("-- HealGuide Ranker Data (Option B)")
        lines.append("-- Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("-- DO NOT EDIT MANUALLY")
        lines.append("")
        lines.append("HGPT_RankerData = {")
        lines.append("    entries = {")

        for entry in entries {
            appendEntry(entry, into: &lines)
        }

        lines.append("    },")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// 파일 저장 경로: <wowAddonsPath>/HealGuide/Data/HGPT_RankerData.lua
    func filePath(wowAddonsPath: String) -> String {
        (wowAddonsPath as NSString)
            .appendingPathComponent("HealGuide/Data/HGPT_RankerData.lua")
    }

    // MARK: - Private

    private func appendEntry(_ entry: HGPTRankerData, into lines: inout [String]) {
        let m = entry.meta
        lines.append("        {")
        lines.append("            _meta = {")
        lines.append("                version          = \(m.version),")
        lines.append("                collectedAt      = \"\(m.collectedAt)\",")
        lines.append("                region           = \"\(m.region)\",")
        lines.append("                dungeonID        = \(m.dungeonID),")
        lines.append("                dungeonName      = \"\(escapeLua(m.dungeonName))\",")
        lines.append("                difficulty       = \"\(escapeLua(m.difficulty))\",")
        lines.append("                spec             = \"\(m.spec)\",")
        lines.append("                rankersRequested = \(m.rankersRequested),")
        lines.append("                rankersUsed      = \(m.rankersUsed),")
        lines.append("                talentFilter     = {")
        lines.append("                    preset     = \"\(escapeLua(m.talentFilterPreset))\",")
        lines.append("                    stringMode = \(m.talentFilterString ? "true" : "false"),")
        lines.append("                    similarity = \(String(format: "%.2f", m.talentFilterSimilarity)),")
        lines.append("                },")
        lines.append("            },")
        lines.append("            data = {")

        for encID in entry.encounterData.keys.sorted() {
            guard let bossMap = entry.encounterData[encID] else { continue }
            lines.append("                [\(encID)] = {")
            for bossID in bossMap.keys.sorted() {
                guard let responses = bossMap[bossID], !responses.isEmpty else { continue }
                lines.append("                    [\(bossID)] = {")
                for response in responses {
                    lines.append("                        {")
                    lines.append("                            spellID = \(response.spellID),")
                    lines.append("                            delay   = \(String(format: "%.2f", response.delay)),")
                    lines.append("                            stddev  = \(String(format: "%.2f", response.stddev)),")
                    lines.append("                            count   = \(response.count),")
                    lines.append("                            quorum  = \"\(response.quorum)\",")
                    lines.append("                        },")
                }
                lines.append("                    },")
            }
            lines.append("                },")
        }

        lines.append("            },")
        lines.append("        },")
    }

    private func escapeLua(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
