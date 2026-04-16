import Foundation
import os

struct SavedVariablesWriter {
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "SavedVariablesWriter")

    func buildDungeonEntry(blocks: [EncounterBlock], spec: HealerSpec, dungeonName: String, sourceURL: String) -> [String: Any] {
        var bosses: [Int: Any] = [:]
        for block in blocks {
            var timeline: [[String: Any]] = []
            for entry in block.absolute {
                var item: [String: Any] = ["spellID": entry.spellID, "offset": entry.offset]
                if entry.condition != nil { item["condition"] = conditionToDict(entry.condition!) }
                timeline.append(item)
            }

            var reactions: [Int: Any] = [:]
            var grouped: [Int: [[String: Any]]] = [:]
            for reaction in block.reactions {
                var item: [String: Any] = ["spellID": reaction.playerSpellID, "delay": reaction.delay]
                if reaction.condition != nil { item["condition"] = conditionToDict(reaction.condition!) }
                grouped[reaction.bossAbilityID, default: []].append(item)
            }
            for (key, value) in grouped { reactions[key] = value }

            var leadIns: [Int: Any] = [:]
            var leadGrouped: [Int: [[String: Any]]] = [:]
            for lead in block.leadIns {
                var item: [String: Any] = ["spellID": lead.playerSpellID, "offset": lead.offset]
                if lead.condition != nil { item["condition"] = conditionToDict(lead.condition!) }
                leadGrouped[lead.bossAbilityID, default: []].append(item)
            }
            for (key, value) in leadGrouped { leadIns[key] = value }

            bosses[block.encounterID] = [
                "name": block.name,
                "duration": block.duration,
                "specs": [
                    spec.rawValue: [
                        "timeline": timeline,
                        "reactions": reactions,
                        "leadIns": leadIns,
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        }

        return [
            "displayName": dungeonName,
            "originalName": dungeonName,
            "sourceURL": sourceURL,
            "importedAt": Int(Date().timeIntervalSince1970),
            "enabled": true,
            "bosses": bosses,
        ]
    }

    func writeToSavedVariables(wtfCharacterPath: String, blocks: [EncounterBlock], spec: HealerSpec, dungeonName: String, sourceURL: String) throws {
        let savedVariablesDirectory = (wtfCharacterPath as NSString).appendingPathComponent("SavedVariables")
        let filePath = (savedVariablesDirectory as NSString).appendingPathComponent("HealGuideCharDB.lua")

        try FileManager.default.createDirectory(atPath: savedVariablesDirectory, withIntermediateDirectories: true)

        let dungeonKey = dungeonName.replacingOccurrences(of: " ", with: "_") + "_\(Int(Date().timeIntervalSince1970))"
        let entry = buildDungeonEntry(blocks: blocks, spec: spec, dungeonName: dungeonName, sourceURL: sourceURL)

        let db: [String: Any] = [
            "version": 1,
            "settings": [:] as [String: Any],
            "encounterIndex": [:] as [String: Any],
            "dungeons": [dungeonKey: entry] as [String: Any],
        ]

        let luaContent = "HealGuideCharDB = " + LuaSerializer.serialize(db) + "\n"
        try luaContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        logger.info("SavedVariables 저장: \(filePath)")
    }

    private func conditionToDict(_ node: ConditionNode) -> [String: Any] {
        var dict: [String: Any] = ["op": node.op]
        if let field = node.field { dict["field"] = field }
        if let value = node.value { dict["value"] = value }
        if let spellID = node.spellID { dict["spellID"] = spellID }
        if let operands = node.operands {
            dict["operands"] = operands.map { conditionToDict($0) }
        }
        return dict
    }
}
