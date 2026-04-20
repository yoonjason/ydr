import Foundation

struct RankerLuaSerializer {
    /// HGPT_RankerData.lua 파일 내용 생성
    func serialize(_ data: HGPTRankerData) -> String {
        var lines: [String] = []
        let meta = data.meta

        lines.append("-- HealGuide Ranker Data")
        lines.append("-- Generated: \(meta.collectedAt)")
        lines.append("-- Region: \(meta.region)  Spec: \(meta.spec)  Dungeon: \(meta.dungeonName)")
        lines.append("-- DO NOT EDIT MANUALLY")
        lines.append("")
        lines.append("HGPT_RankerData = {")
        lines.append("    _meta = {")
        lines.append("        version          = \(meta.version),")
        lines.append("        collectedAt      = \"\(meta.collectedAt)\",")
        lines.append("        region           = \"\(meta.region)\",")
        lines.append("        dungeonID        = \(meta.dungeonID),")
        lines.append("        dungeonName      = \"\(escapeLua(meta.dungeonName))\",")
        lines.append("        difficulty       = \"\(meta.difficulty)\",")
        lines.append("        spec             = \"\(meta.spec)\",")
        lines.append("        rankersRequested = \(meta.rankersRequested),")
        lines.append("        rankersUsed      = \(meta.rankersUsed),")
        lines.append("        talentFilter     = {")
        lines.append("            preset     = \"\(escapeLua(meta.talentFilterPreset))\",")
        lines.append("            stringMode = \(meta.talentFilterString ? "true" : "false"),")
        lines.append("            similarity = \(String(format: "%.2f", meta.talentFilterSimilarity)),")
        lines.append("        },")
        lines.append("    },")

        for encID in data.encounterData.keys.sorted() {
            guard let bossMap = data.encounterData[encID] else { continue }
            lines.append("    [\(encID)] = {")
            for bossID in bossMap.keys.sorted() {
                guard let entries = bossMap[bossID], !entries.isEmpty else { continue }
                lines.append("        [\(bossID)] = {")
                for entry in entries {
                    lines.append("            {")
                    lines.append("                spellID = \(entry.spellID),")
                    lines.append("                delay   = \(String(format: "%.2f", entry.delay)),")
                    lines.append("                stddev  = \(String(format: "%.2f", entry.stddev)),")
                    lines.append("                count   = \(entry.count),")
                    lines.append("                quorum  = \"\(entry.quorum)\",")
                    lines.append("            },")
                }
                lines.append("        },")
            }
            lines.append("    },")
        }

        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// 파일 저장 경로: <wowAddonsPath>/HealGuide/Data/HGPT_RankerData.lua
    func filePath(wowAddonsPath: String) -> String {
        (wowAddonsPath as NSString)
            .appendingPathComponent("HealGuide/Data/HGPT_RankerData.lua")
    }

    private func escapeLua(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
