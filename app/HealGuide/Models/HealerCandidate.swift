import Foundation

struct HealerCandidate: Equatable, Hashable, Identifiable {
    let id: Int          // actor ID (WarcraftLogs source ID)
    let name: String
    let className: String     // "Priest"
    let specName: String      // "Discipline"
    let server: String?

    var healerSpec: HealerSpec? {
        HealerCandidate.specMap[specKey]
    }

    var displayName: String {
        if let hs = healerSpec {
            return "\(name) — \(hs.displayName)"
        }
        return "\(name) — \(specName) \(className)"
    }

    private var specKey: String {
        "\(specName)\(className)"
    }

    private static let specMap: [String: HealerSpec] = [
        "DisciplinePriest":   .discPriest,
        "HolyPriest":         .holyPriest,
        "RestorationDruid":   .restoDruid,
        "MistweaverMonk":     .mistweaverMonk,
        "HolyPaladin":        .holyPaladin,
        "RestorationShaman":  .restoShaman,
        "PreservationEvoker": .presEvoker,
    ]
}
