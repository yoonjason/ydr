import Foundation

// Midnight(12.0) 기준 힐러 스펙별 캐스트 가능 스킬 카탈로그.
//
// 범위: 전투 로그에 cast 이벤트로 등장하는 스킬만 포함 (패시브/프록 제외).
// 이름은 한국어 우선, 영어 폴백. Spell ID 는 Midnight 기준으로 검증된 값.
// 미검증 또는 버전별 변경 가능성이 있는 항목은 주석으로 표기.
//
// 갱신 정책:
// - 로그에서 카탈로그에 없는 스킬 발견 시 앱 UI 에서 사용자 확인 후 추가
// - Midnight 이후 패치로 spell ID 가 변하면 여기서 일괄 갱신
//
// 참고:
// - Wowhead: https://www.wowhead.com/spell=<id>
// - Icy Veins Midnight 가이드
// - WarcraftLogs masterData.abilities 런타임 조회 폴백

struct SpellEntry: Equatable, Hashable, Identifiable {
    let id: Int          // spellID
    let nameKR: String
    let nameEN: String
}

enum SpecSpellCatalog {
    static let catalog: [HealerSpec: [SpellEntry]] = [
        .discPriest:   discPriest,
        .holyPriest:   holyPriest,
        .restoDruid:   [],     // TODO: S3
        .mistweaverMonk: [],   // TODO: S3
        .holyPaladin:  [],     // TODO: S3
        .restoShaman:  [],     // TODO: S3
        .presEvoker:   [],     // TODO: S3
    ]

    static func spells(for spec: HealerSpec) -> [SpellEntry] {
        catalog[spec] ?? []
    }

    // MARK: - Discipline Priest (Midnight)

    private static let discPriest: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 17,     nameKR: "신의 권능: 보호막",     nameEN: "Power Word: Shield"),
        SpellEntry(id: 2061,   nameKR: "순간 치유",             nameEN: "Flash Heal"),
        SpellEntry(id: 585,    nameKR: "성스러운 일격",         nameEN: "Smite"),
        SpellEntry(id: 589,    nameKR: "어둠의 권능: 고통",     nameEN: "Shadow Word: Pain"),
        SpellEntry(id: 8092,   nameKR: "정신 분열",             nameEN: "Mind Blast"),
        SpellEntry(id: 47540,  nameKR: "참회",                  nameEN: "Penance"),
        SpellEntry(id: 527,    nameKR: "정화",                  nameEN: "Purify"),
        SpellEntry(id: 21562,  nameKR: "신의 권능: 인내",       nameEN: "Power Word: Fortitude"),
        SpellEntry(id: 212036, nameKR: "대규모 부활",           nameEN: "Mass Resurrection"),
        SpellEntry(id: 1706,   nameKR: "공중 부양",             nameEN: "Levitate"),
        SpellEntry(id: 453,    nameKR: "정신 진정",             nameEN: "Mind Soothe"),

        // Class tree
        SpellEntry(id: 121536, nameKR: "천사의 깃털",           nameEN: "Angelic Feather"),
        SpellEntry(id: 528,    nameKR: "마법 무효화",           nameEN: "Dispel Magic"),
        SpellEntry(id: 132157, nameKR: "성스러운 폭발",         nameEN: "Holy Nova"),
        SpellEntry(id: 73325,  nameKR: "신념의 도약",           nameEN: "Leap of Faith"),
        SpellEntry(id: 9484,   nameKR: "공포 속박",             nameEN: "Shackle Horror"), // Midnight 에서 Shackle Undead 계열 재명명
        SpellEntry(id: 605,    nameKR: "정신 지배",             nameEN: "Mind Control"),
        SpellEntry(id: 32375,  nameKR: "대규모 무효화",         nameEN: "Mass Dispel"),
        SpellEntry(id: 10060,  nameKR: "마력 주입",             nameEN: "Power Infusion"),
        SpellEntry(id: 19236,  nameKR: "필사의 기도",           nameEN: "Desperate Prayer"),
        SpellEntry(id: 586,    nameKR: "소실",                  nameEN: "Fade"),
        SpellEntry(id: 32379,  nameKR: "어둠의 권능: 죽음",     nameEN: "Shadow Word: Death"),
        SpellEntry(id: 8122,   nameKR: "내면의 공포",           nameEN: "Psychic Scream"),

        // Spec tree (Disc)
        SpellEntry(id: 194509, nameKR: "신의 권능: 광휘",       nameEN: "Power Word: Radiance"),
        SpellEntry(id: 33206,  nameKR: "고통 억제",             nameEN: "Pain Suppression"),
        SpellEntry(id: 62618,  nameKR: "신의 권능: 방벽",       nameEN: "Power Word: Barrier"),
        SpellEntry(id: 421434, nameKR: "궁극의 참회",           nameEN: "Ultimate Penitence"),
        SpellEntry(id: 246287, nameKR: "복음",                  nameEN: "Evangelism"),
        SpellEntry(id: 34433,  nameKR: "어둠의 친구",           nameEN: "Shadowfiend"),
        SpellEntry(id: 123040, nameKR: "정신 지배자",           nameEN: "Mindbender"),

        // Hero talents — Voidweaver
        SpellEntry(id: 447444, nameKR: "혼돈의 균열",           nameEN: "Entropic Rift"),
        SpellEntry(id: 451234, nameKR: "공허 망령",             nameEN: "Voidwraith"),
    ]

    // MARK: - Holy Priest (Midnight)

    private static let holyPriest: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 2061,   nameKR: "순간 치유",             nameEN: "Flash Heal"),
        SpellEntry(id: 2060,   nameKR: "치유",                  nameEN: "Heal"),
        SpellEntry(id: 139,    nameKR: "소생",                  nameEN: "Renew"),
        SpellEntry(id: 17,     nameKR: "신의 권능: 보호막",     nameEN: "Power Word: Shield"),
        SpellEntry(id: 585,    nameKR: "성스러운 일격",         nameEN: "Smite"),
        SpellEntry(id: 589,    nameKR: "어둠의 권능: 고통",     nameEN: "Shadow Word: Pain"),
        SpellEntry(id: 14914,  nameKR: "신성한 불꽃",           nameEN: "Holy Fire"),
        SpellEntry(id: 33076,  nameKR: "치유의 기원",           nameEN: "Prayer of Mending"),
        SpellEntry(id: 527,    nameKR: "정화",                  nameEN: "Purify"),
        SpellEntry(id: 21562,  nameKR: "신의 권능: 인내",       nameEN: "Power Word: Fortitude"),
        SpellEntry(id: 212036, nameKR: "대규모 부활",           nameEN: "Mass Resurrection"),
        SpellEntry(id: 1706,   nameKR: "공중 부양",             nameEN: "Levitate"),
        SpellEntry(id: 453,    nameKR: "정신 진정",             nameEN: "Mind Soothe"),

        // Class tree (공용)
        SpellEntry(id: 121536, nameKR: "천사의 깃털",           nameEN: "Angelic Feather"),
        SpellEntry(id: 528,    nameKR: "마법 무효화",           nameEN: "Dispel Magic"),
        SpellEntry(id: 132157, nameKR: "성스러운 폭발",         nameEN: "Holy Nova"),
        SpellEntry(id: 73325,  nameKR: "신념의 도약",           nameEN: "Leap of Faith"),
        SpellEntry(id: 9484,   nameKR: "공포 속박",             nameEN: "Shackle Horror"),
        SpellEntry(id: 605,    nameKR: "정신 지배",             nameEN: "Mind Control"),
        SpellEntry(id: 32375,  nameKR: "대규모 무효화",         nameEN: "Mass Dispel"),
        SpellEntry(id: 10060,  nameKR: "마력 주입",             nameEN: "Power Infusion"),
        SpellEntry(id: 19236,  nameKR: "필사의 기도",           nameEN: "Desperate Prayer"),
        SpellEntry(id: 586,    nameKR: "소실",                  nameEN: "Fade"),
        SpellEntry(id: 32379,  nameKR: "어둠의 권능: 죽음",     nameEN: "Shadow Word: Death"),
        SpellEntry(id: 8122,   nameKR: "내면의 공포",           nameEN: "Psychic Scream"),

        // Spec tree (Holy)
        SpellEntry(id: 596,    nameKR: "치유의 기도",           nameEN: "Prayer of Healing"),
        SpellEntry(id: 2050,   nameKR: "신성한 언령: 평온",     nameEN: "Holy Word: Serenity"),
        SpellEntry(id: 34861,  nameKR: "신성한 언령: 축성",     nameEN: "Holy Word: Sanctify"),
        SpellEntry(id: 88625,  nameKR: "신성한 언령: 응징",     nameEN: "Holy Word: Chastise"),
        SpellEntry(id: 47788,  nameKR: "수호 영혼",             nameEN: "Guardian Spirit"),
        SpellEntry(id: 64843,  nameKR: "천상의 찬가",           nameEN: "Divine Hymn"),
        SpellEntry(id: 200183, nameKR: "신격화",                nameEN: "Apotheosis"),
    ]
}
