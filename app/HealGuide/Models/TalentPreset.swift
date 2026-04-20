import Foundation

struct TalentPreset: Identifiable, Hashable {
    let id: String                     // e.g. "DiscPriest_Evangelism"
    let specKey: HealerSpec
    let name: String
    // TODO: Populate with actual TWW season talent node IDs.
    // Node IDs can be found via:
    //   - WarcraftLogs characterRankings response .talents[].id
    //   - Blizzard API: /data/wow/talent-tree/{treeID}/spec/{specID}
    // Empty set = no requirement (matches everything).
    let coreTalentNodeIDs:    Set<Int>
    let excludeTalentNodeIDs: Set<Int>
}

enum TalentPresetCatalog {
    static let all: [TalentPreset] = [
        // MARK: Discipline Priest
        TalentPreset(
            id: "DiscPriest_Evangelism",
            specKey: .discPriest,
            name: "Evangelism",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []   // TODO: Oracle node IDs
        ),
        TalentPreset(
            id: "DiscPriest_Oracle",
            specKey: .discPriest,
            name: "Oracle",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []   // TODO: Evangelism node IDs
        ),
        TalentPreset(
            id: "DiscPriest_Voidweaver",
            specKey: .discPriest,
            name: "Voidweaver",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),

        // MARK: Holy Priest
        TalentPreset(
            id: "HolyPriest_HolyWord",
            specKey: .holyPriest,
            name: "Holy Word",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
        TalentPreset(
            id: "HolyPriest_Lightweaver",
            specKey: .holyPriest,
            name: "Lightweaver",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),

        // MARK: Restoration Druid
        TalentPreset(
            id: "RestoDruid_Flourish",
            specKey: .restoDruid,
            name: "Flourish",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
        TalentPreset(
            id: "RestoDruid_Cenarius",
            specKey: .restoDruid,
            name: "Cenarius' Might",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),

        // MARK: Mistweaver Monk
        TalentPreset(
            id: "MistweaverMonk_MistWeavers",
            specKey: .mistweaverMonk,
            name: "Jadefire Stomp",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
        TalentPreset(
            id: "MistweaverMonk_Invoker",
            specKey: .mistweaverMonk,
            name: "Invoker",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),

        // MARK: Holy Paladin
        TalentPreset(
            id: "HolyPaladin_Glimmer",
            specKey: .holyPaladin,
            name: "Glimmer of Light",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
        TalentPreset(
            id: "HolyPaladin_Herald",
            specKey: .holyPaladin,
            name: "Herald of the Sun",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),

        // MARK: Restoration Shaman
        TalentPreset(
            id: "RestoShaman_Tidewaves",
            specKey: .restoShaman,
            name: "Tidewaves",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
        TalentPreset(
            id: "RestoShaman_Farseer",
            specKey: .restoShaman,
            name: "Farseer",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),

        // MARK: Preservation Evoker
        TalentPreset(
            id: "PresEvoker_Standard",
            specKey: .presEvoker,
            name: "Standard",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
        TalentPreset(
            id: "PresEvoker_Temporal",
            specKey: .presEvoker,
            name: "Temporal Anomaly",
            coreTalentNodeIDs:    [],  // TODO
            excludeTalentNodeIDs: []
        ),
    ]

    static func presets(for spec: HealerSpec) -> [TalentPreset] {
        all.filter { $0.specKey == spec }
    }
}

// MARK: - WarcraftLogs 스펙 매핑

extension HealerSpec {
    var warcraftLogsClassName: String {
        switch self {
        case .discPriest, .holyPriest: return "Priest"
        case .restoDruid:              return "Druid"
        case .mistweaverMonk:          return "Monk"
        case .holyPaladin:             return "Paladin"
        case .restoShaman:             return "Shaman"
        case .presEvoker:              return "Evoker"
        }
    }

    var warcraftLogsSpecName: String {
        switch self {
        case .discPriest:      return "Discipline"
        case .holyPriest:      return "Holy"
        case .restoDruid:      return "Restoration"
        case .mistweaverMonk:  return "Mistweaver"
        case .holyPaladin:     return "Holy"
        case .restoShaman:     return "Restoration"
        case .presEvoker:      return "Preservation"
        }
    }
}
