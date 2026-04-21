import Foundation

// 힐러 스킬 카테고리. 베타 쿨타임 fallback 에서 "같은 카테고리 내 대체" 로직 지원.
// 카테고리 태깅 안 된 스킬은 nil → 단순 순위 fallback 만 적용.
//
// 범위: DiscPriest + HolyPriest 우선 (사용자 요청). 다른 스펙은 향후 추가.
// 큐레이션 기준: 2026 시즌 Midnight 기준 주요 힐링 스킬 + 디펜시브/유틸.
enum HealerSpellCategory: String, Codable {
    case aoeHeal     // 광역 힐 (Divine Star, Halo, Prayer of Healing, ...)
    case singleHeal  // 단일 힐 (Penance, Flash Heal, Heal, ...)
    case shield      // 흡수 쉴드 (Power Word: Shield)
    case hot         // 지속 회복 (Renew, Prayer of Mending)
    case defensive   // 디펜시브 쿨다운 (Pain Suppression, Guardian Spirit, Barrier)
    case emergency   // 긴급/대용량 (Divine Hymn, Apotheosis, Rapture)
    case dispel      // 정화 (Purify, Mass Dispel)
    case utility     // 유틸 (Shadowfiend, Symbol of Hope — 마나/버프)

    var displayName: String {
        switch self {
        case .aoeHeal:    return "광역힐"
        case .singleHeal: return "단일힐"
        case .shield:     return "쉴드"
        case .hot:        return "HOT"
        case .defensive:  return "디펜시브"
        case .emergency:  return "긴급"
        case .dispel:     return "정화"
        case .utility:    return "유틸"
        }
    }
}

enum HealerSpellCategoryCatalog {
    /// spec + spellID → 카테고리. 태깅 안 된 스킬은 nil.
    static func category(for spellID: Int, spec: HealerSpec) -> HealerSpellCategory? {
        switch spec {
        case .discPriest: return discPriest[spellID]
        case .holyPriest: return holyPriest[spellID]
        default:          return nil   // 다른 스펙은 향후 확장
        }
    }

    /// 해당 스펙에서 카테고리가 태깅된 모든 spellID.
    /// 맥 앱 시뮬레이션 탭의 '쿨타임 입력 체크박스' 용도.
    static func knownSpellIDs(for spec: HealerSpec) -> [Int] {
        switch spec {
        case .discPriest: return Array(discPriest.keys).sorted()
        case .holyPriest: return Array(holyPriest.keys).sorted()
        default:          return []
        }
    }

    // MARK: - DiscPriest (수양 사제)

    private static let discPriest: [Int: HealerSpellCategory] = [
        17:     .shield,       // Power Word: Shield
        47540:  .singleHeal,   // Penance (힐링 타겟 기준)
        186263: .singleHeal,   // Shadow Mend
        194509: .aoeHeal,      // Power Word: Radiance
        110744: .aoeHeal,      // Divine Star (탤런트)
        120517: .aoeHeal,      // Halo (탤런트)
        33206:  .defensive,    // Pain Suppression (단일 대상 디펜)
        62618:  .defensive,    // Power Word: Barrier (광역 디펜)
        33076:  .hot,          // Prayer of Mending (팅겨다니는 HOT)
        246287: .emergency,    // Rapture (광역 쉴드 뿌리기)
        472433: .emergency,    // Ultimate Penitence (12.0 대기술)
        527:    .dispel,       // Purify (단일 정화)
        32375:  .dispel,       // Mass Dispel (광역 정화)
        34433:  .utility,      // Shadowfiend (마나)
        123040: .utility,      // Mindbender (마나)
    ]

    // MARK: - HolyPriest (신성 사제)

    private static let holyPriest: [Int: HealerSpellCategory] = [
        2061:   .singleHeal,   // Flash Heal
        2060:   .singleHeal,   // Heal
        139:    .hot,          // Renew
        33076:  .hot,          // Prayer of Mending
        596:    .aoeHeal,      // Prayer of Healing
        34861:  .aoeHeal,      // Holy Word: Sanctify (광역 프록힐)
        204883: .aoeHeal,      // Circle of Healing
        110744: .aoeHeal,      // Divine Star
        120517: .aoeHeal,      // Halo
        2050:   .singleHeal,   // Holy Word: Serenity (프록힐 단일)
        47788:  .defensive,    // Guardian Spirit (사망 방지)
        64843:  .emergency,    // Divine Hymn
        200183: .emergency,    // Apotheosis
        265202: .utility,      // Symbol of Hope (파티 마나)
        527:    .dispel,       // Purify
        32375:  .dispel,       // Mass Dispel
    ]
}
