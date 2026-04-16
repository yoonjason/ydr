enum HealerSpec: String, CaseIterable, Identifiable {
    case discPriest = "DiscPriest"
    case holyPriest = "HolyPriest"
    case restoDruid = "RestoDruid"
    case mistweaverMonk = "MistweaverMonk"
    case holyPaladin = "HolyPaladin"
    case restoShaman = "RestoShaman"
    case presEvoker = "PresEvoker"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .discPriest:      return "수양 사제"
        case .holyPriest:      return "신성 사제"
        case .restoDruid:      return "회복 드루이드"
        case .mistweaverMonk:  return "운무 수도사"
        case .holyPaladin:     return "신성 성기사"
        case .restoShaman:     return "복원 주술사"
        case .presEvoker:      return "보존 기원사"
        }
    }

    var blizzardSpecID: Int {
        switch self {
        case .discPriest:      return 256
        case .holyPriest:      return 257
        case .restoDruid:      return 105
        case .mistweaverMonk:  return 270
        case .holyPaladin:     return 65
        case .restoShaman:     return 264
        case .presEvoker:      return 1468
        }
    }
}
