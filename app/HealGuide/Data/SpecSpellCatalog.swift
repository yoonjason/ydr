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
        .discPriest:     discPriest,
        .holyPriest:     holyPriest,
        .restoDruid:     restoDruid,
        .mistweaverMonk: mistweaverMonk,
        .holyPaladin:    holyPaladin,
        .restoShaman:    restoShaman,
        .presEvoker:     presEvoker,
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

    // MARK: - Restoration Druid (Midnight)

    private static let restoDruid: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 774,    nameKR: "회복",                  nameEN: "Rejuvenation"),
        SpellEntry(id: 8936,   nameKR: "회복지정",              nameEN: "Regrowth"),
        SpellEntry(id: 48438,  nameKR: "급속 성장",             nameEN: "Wild Growth"),
        SpellEntry(id: 18562,  nameKR: "신속한 치유",           nameEN: "Swiftmend"),
        SpellEntry(id: 33763,  nameKR: "피어나는 생명",         nameEN: "Lifebloom"),
        SpellEntry(id: 145205, nameKR: "개화",                  nameEN: "Efflorescence"),
        SpellEntry(id: 740,    nameKR: "평온",                  nameEN: "Tranquility"),
        SpellEntry(id: 5176,   nameKR: "천벌",                  nameEN: "Wrath"),
        SpellEntry(id: 8921,   nameKR: "달빛섬광",              nameEN: "Moonfire"),
        SpellEntry(id: 93402,  nameKR: "태양섬광",              nameEN: "Sunfire"),

        // Class tree
        SpellEntry(id: 132158, nameKR: "자연의 신속함",         nameEN: "Nature's Swiftness"),
        SpellEntry(id: 22812,  nameKR: "나무 껍질",             nameEN: "Barkskin"),
        SpellEntry(id: 22842,  nameKR: "광폭한 재생력",         nameEN: "Frenzied Regeneration"),
        SpellEntry(id: 1126,   nameKR: "야생의 징표",           nameEN: "Mark of the Wild"),
        SpellEntry(id: 20484,  nameKR: "환생",                  nameEN: "Rebirth"),
        SpellEntry(id: 102342, nameKR: "무쇠나무 껍질",         nameEN: "Ironbark"),
        SpellEntry(id: 29166,  nameKR: "energize",              nameEN: "Innervate"),
        SpellEntry(id: 339,    nameKR: "휘감는 뿌리",           nameEN: "Entangling Roots"),
        SpellEntry(id: 102401, nameKR: "야생 질주",             nameEN: "Wild Charge"),
        SpellEntry(id: 33786,  nameKR: "사이클론",              nameEN: "Cyclone"),
        SpellEntry(id: 2908,   nameKR: "진정",                  nameEN: "Soothe"),
        SpellEntry(id: 132469, nameKR: "태풍",                  nameEN: "Typhoon"),
        SpellEntry(id: 106898, nameKR: "쇄도의 포효",           nameEN: "Stampeding Roar"),
        SpellEntry(id: 99,     nameKR: "무력화의 포효",         nameEN: "Incapacitating Roar"),
        SpellEntry(id: 5211,   nameKR: "강타",                  nameEN: "Mighty Bash"),
        SpellEntry(id: 5215,   nameKR: "은신",                  nameEN: "Prowl"),
        SpellEntry(id: 102793, nameKR: "우르솔의 소용돌이",     nameEN: "Ursol's Vortex"),
        SpellEntry(id: 102359, nameKR: "군중 휘감기",           nameEN: "Mass Entanglement"),
        SpellEntry(id: 2637,   nameKR: "곰의 잠",               nameEN: "Hibernate"),

        // Spec tree
        SpellEntry(id: 33891,  nameKR: "화신: 생명의 나무",     nameEN: "Incarnation: Tree of Life"),
        SpellEntry(id: 391528, nameKR: "영혼 소집",             nameEN: "Convoke the Spirits"),
        SpellEntry(id: 197628, nameKR: "별빛섬광",              nameEN: "Starfire"),
        SpellEntry(id: 197626, nameKR: "별빛쇄도",              nameEN: "Starsurge"),
    ]

    // MARK: - Mistweaver Monk (Midnight)

    private static let mistweaverMonk: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 115151, nameKR: "재생의 안개",           nameEN: "Renewing Mist"),
        SpellEntry(id: 116670, nameKR: "소생",                  nameEN: "Vivify"),
        SpellEntry(id: 124682, nameKR: "포영의 안개",           nameEN: "Enveloping Mist"),
        SpellEntry(id: 107428, nameKR: "해오름차기",            nameEN: "Rising Sun Kick"),
        SpellEntry(id: 100784, nameKR: "후려차기",              nameEN: "Blackout Kick"),
        SpellEntry(id: 100780, nameKR: "범의 장풍",             nameEN: "Tiger Palm"),
        SpellEntry(id: 101546, nameKR: "회전 학다리차기",       nameEN: "Spinning Crane Kick"),
        SpellEntry(id: 117952, nameKR: "폭풍 옥룡의 번개",      nameEN: "Crackling Jade Lightning"),
        SpellEntry(id: 218164, nameKR: "해독",                  nameEN: "Detox"),
        SpellEntry(id: 119381, nameKR: "회축",                  nameEN: "Leg Sweep"),
        SpellEntry(id: 115546, nameKR: "도발",                  nameEN: "Provoke"),
        SpellEntry(id: 212051, nameKR: "소생술",                nameEN: "Reawaken"),
        SpellEntry(id: 109132, nameKR: "구르기",                nameEN: "Roll"),

        // Class tree
        SpellEntry(id: 115175, nameKR: "평온의 안개",           nameEN: "Soothing Mist"),
        SpellEntry(id: 115078, nameKR: "기절",                  nameEN: "Paralysis"),
        SpellEntry(id: 116841, nameKR: "범의 욕망",             nameEN: "Tiger's Lust"),
        SpellEntry(id: 116095, nameKR: "무력화",                nameEN: "Disable"),
        SpellEntry(id: 116680, nameKR: "벽력의 집중차",         nameEN: "Thunder Focus Tea"),
        SpellEntry(id: 116849, nameKR: "생명의 고치",           nameEN: "Life Cocoon"),
        SpellEntry(id: 197908, nameKR: "마력차",                nameEN: "Mana Tea"),
        SpellEntry(id: 115310, nameKR: "소생",                  nameEN: "Revival"),
        SpellEntry(id: 388615, nameKR: "회복의 기운",           nameEN: "Restoral"),
        SpellEntry(id: 101643, nameKR: "초월",                  nameEN: "Transcendence"),
        SpellEntry(id: 116844, nameKR: "평화의 고리",           nameEN: "Ring of Peace"),
        SpellEntry(id: 198898, nameKR: "적기린의 노래",         nameEN: "Song of Chi-Ji"),
        SpellEntry(id: 115203, nameKR: "강화주",                nameEN: "Fortifying Brew"),
        SpellEntry(id: 322118, nameKR: "유룡 소환",             nameEN: "Invoke Yu'lon"),
        SpellEntry(id: 325197, nameKR: "적기린 소환",           nameEN: "Invoke Chi-Ji"),
        SpellEntry(id: 450391, nameKR: "기의 파도",             nameEN: "Chi Wave"),

        // Spec tree
        SpellEntry(id: 115313, nameKR: "옥룡 석상 소환",        nameEN: "Summon Jade Serpent Statue"),
        SpellEntry(id: 451259, nameKR: "쇄풍차기",              nameEN: "Rushing Wind Kick"),
        SpellEntry(id: 399491, nameKR: "쉐이룬의 선물",         nameEN: "Sheilun's Gift"),

        // Hero — Conduit of the Celestials
        SpellEntry(id: 443028, nameKR: "천신의 도관",           nameEN: "Celestial Conduit"),
        SpellEntry(id: 388193, nameKR: "옥염진각",              nameEN: "Jadefire Stomp"),
        SpellEntry(id: 123986, nameKR: "기의 쇄도",             nameEN: "Chi Burst"),
    ]

    // MARK: - Holy Paladin (Midnight)

    private static let holyPaladin: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 20473,  nameKR: "신성 충격",             nameEN: "Holy Shock"),
        SpellEntry(id: 85673,  nameKR: "영광의 서약",           nameEN: "Word of Glory"),
        SpellEntry(id: 85222,  nameKR: "여명의 빛",             nameEN: "Light of Dawn"),
        SpellEntry(id: 20271,  nameKR: "심판",                  nameEN: "Judgment"),
        SpellEntry(id: 19750,  nameKR: "빛의 섬광",             nameEN: "Flash of Light"),
        SpellEntry(id: 82326,  nameKR: "성스러운 빛",           nameEN: "Holy Light"),
        SpellEntry(id: 53563,  nameKR: "빛의 봉화",             nameEN: "Beacon of Light"),
        SpellEntry(id: 4987,   nameKR: "정화",                  nameEN: "Cleanse"),
        SpellEntry(id: 498,    nameKR: "천상의 보호막",         nameEN: "Divine Protection"),
        SpellEntry(id: 642,    nameKR: "천상의 방패",           nameEN: "Divine Shield"),
        SpellEntry(id: 190784, nameKR: "성전의 군마",           nameEN: "Divine Steed"),
        SpellEntry(id: 391054, nameKR: "중재",                  nameEN: "Intercession"),
        SpellEntry(id: 1022,   nameKR: "보호의 축복",           nameEN: "Blessing of Protection"),
        SpellEntry(id: 1044,   nameKR: "자유의 축복",           nameEN: "Blessing of Freedom"),
        SpellEntry(id: 853,    nameKR: "심판의 망치",           nameEN: "Hammer of Justice"),
        SpellEntry(id: 115750, nameKR: "실명의 빛",             nameEN: "Blinding Light"),

        // Class / Spec tree
        SpellEntry(id: 53600,  nameKR: "정의의 방패",           nameEN: "Shield of the Righteous"),
        SpellEntry(id: 26573,  nameKR: "신성화",                nameEN: "Consecration"),
        SpellEntry(id: 114165, nameKR: "성스러운 프리즘",       nameEN: "Holy Prism"),
        SpellEntry(id: 31821,  nameKR: "오라 숙련",             nameEN: "Aura Mastery"),
        SpellEntry(id: 31884,  nameKR: "응징의 격노",           nameEN: "Avenging Wrath"),
        SpellEntry(id: 216331, nameKR: "응징의 성전사",         nameEN: "Avenging Crusader"),
        SpellEntry(id: 375576, nameKR: "천상의 조종",           nameEN: "Divine Toll"),

        // Hero talents
        SpellEntry(id: 156322, nameKR: "영원한 불꽃",           nameEN: "Eternal Flame"),
        SpellEntry(id: 432459, nameKR: "신성 무장",             nameEN: "Holy Armaments"),
    ]

    // MARK: - Restoration Shaman (Midnight)

    private static let restoShaman: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 188196, nameKR: "번개 화살",             nameEN: "Lightning Bolt"),
        SpellEntry(id: 188389, nameKR: "불길 쇼크",             nameEN: "Flame Shock"),
        SpellEntry(id: 77472,  nameKR: "치유의 파도",           nameEN: "Healing Wave"),
        SpellEntry(id: 2825,   nameKR: "피의 욕망",             nameEN: "Bloodlust"),
        SpellEntry(id: 32182,  nameKR: "영웅심",                nameEN: "Heroism"),
        SpellEntry(id: 2484,   nameKR: "대지 결박 토템",        nameEN: "Earthbind Totem"),
        SpellEntry(id: 2645,   nameKR: "늑대 정령",             nameEN: "Ghost Wolf"),
        SpellEntry(id: 2008,   nameKR: "고대의 영혼",           nameEN: "Ancestral Spirit"),
        SpellEntry(id: 546,    nameKR: "물 위 걷기",            nameEN: "Water Walking"),

        // Class tree
        SpellEntry(id: 1064,   nameKR: "연쇄 치유",             nameEN: "Chain Heal"),
        SpellEntry(id: 51505,  nameKR: "용암 폭발",             nameEN: "Lava Burst"),
        SpellEntry(id: 188443, nameKR: "연쇄 번개",             nameEN: "Chain Lightning"),
        SpellEntry(id: 198103, nameKR: "대지 정령",             nameEN: "Earth Elemental"),
        SpellEntry(id: 57994,  nameKR: "바람 베기",             nameEN: "Wind Shear"),
        SpellEntry(id: 196840, nameKR: "냉기 쇼크",             nameEN: "Frost Shock"),
        SpellEntry(id: 974,    nameKR: "대지의 보호막",         nameEN: "Earth Shield"),
        SpellEntry(id: 58875,  nameKR: "정령 걷기",             nameEN: "Spirit Walk"),
        SpellEntry(id: 192058, nameKR: "축전 토템",             nameEN: "Capacitor Totem"),
        SpellEntry(id: 77130,  nameKR: "영혼 정화",             nameEN: "Purify Spirit"),
        SpellEntry(id: 370,    nameKR: "정화",                  nameEN: "Purge"),
        SpellEntry(id: 192077, nameKR: "바람 쇄도 토템",        nameEN: "Wind Rush Totem"),
        SpellEntry(id: 51485,  nameKR: "대지 붙잡기 토템",      nameEN: "Earthgrab Totem"),
        SpellEntry(id: 51514,  nameKR: "변이",                  nameEN: "Hex"),
        SpellEntry(id: 5394,   nameKR: "치유의 토템",           nameEN: "Healing Stream Totem"),
        SpellEntry(id: 79206,  nameKR: "정령 방랑자의 은총",    nameEN: "Spiritwalker's Grace"),
        SpellEntry(id: 378081, nameKR: "자연의 신속함",         nameEN: "Nature's Swiftness"),
        SpellEntry(id: 8143,   nameKR: "진동 토템",             nameEN: "Tremor Totem"),
        SpellEntry(id: 383013, nameKR: "독 정화 토템",          nameEN: "Poison Cleansing Totem"),

        // Resto tree
        SpellEntry(id: 61295,  nameKR: "성난 해일",             nameEN: "Riptide"),
        SpellEntry(id: 73920,  nameKR: "치유의 비",             nameEN: "Healing Rain"),
        SpellEntry(id: 114052, nameKR: "정령체",                nameEN: "Ascendance"),
        SpellEntry(id: 108280, nameKR: "치유의 해일 토템",      nameEN: "Healing Tide Totem"),
        SpellEntry(id: 73685,  nameKR: "생명의 해방",           nameEN: "Unleash Life"),
        SpellEntry(id: 98008,  nameKR: "영혼 결속 토템",        nameEN: "Spirit Link Totem"),

        // Hero talents
        SpellEntry(id: 443454, nameKR: "선조의 부름",           nameEN: "Call of the Ancestors"),
        SpellEntry(id: 443454, nameKR: "선조의 신속",           nameEN: "Ancestral Swiftness"), // TODO ID 확인
        SpellEntry(id: 444995, nameKR: "파동 토템",             nameEN: "Surging Totem"),
    ]

    // MARK: - Preservation Evoker (Midnight)

    private static let presEvoker: [SpellEntry] = [
        // Baseline
        SpellEntry(id: 361469, nameKR: "살아있는 불꽃",         nameEN: "Living Flame"),
        SpellEntry(id: 362969, nameKR: "하늘빛 일격",           nameEN: "Azure Strike"),
        SpellEntry(id: 357210, nameKR: "깊은 숨결",             nameEN: "Deep Breath"),

        // Spec tree
        SpellEntry(id: 364343, nameKR: "메아리",                nameEN: "Echo"),
        SpellEntry(id: 366155, nameKR: "되돌리기",              nameEN: "Reversion"),
        SpellEntry(id: 355913, nameKR: "에메랄드의 꽃",         nameEN: "Emerald Blossom"),
        SpellEntry(id: 355936, nameKR: "꿈결 숨결",             nameEN: "Dream Breath"),
        SpellEntry(id: 360995, nameKR: "신록의 포옹",           nameEN: "Verdant Embrace"),
        SpellEntry(id: 373861, nameKR: "시간의 변칙",           nameEN: "Temporal Anomaly"),
        SpellEntry(id: 360823, nameKR: "자연화",                nameEN: "Naturalize"),
        SpellEntry(id: 374251, nameKR: "소작의 불꽃",           nameEN: "Cauterizing Flame"),
        SpellEntry(id: 357208, nameKR: "불 숨결",               nameEN: "Fire Breath"),
        SpellEntry(id: 356995, nameKR: "분해",                  nameEN: "Disintegrate"),

        // Defensive / Utility
        SpellEntry(id: 363916, nameKR: "흑요석 비늘",           nameEN: "Obsidian Scales"),
        SpellEntry(id: 357170, nameKR: "시간 팽창",             nameEN: "Time Dilation"),
        SpellEntry(id: 374227, nameKR: "산들바람",              nameEN: "Zephyr"),
        SpellEntry(id: 358267, nameKR: "부양",                  nameEN: "Hover"),
        SpellEntry(id: 370665, nameKR: "구출",                  nameEN: "Rescue"),
        SpellEntry(id: 357214, nameKR: "날개 강타",             nameEN: "Wing Buffet"),
        SpellEntry(id: 368970, nameKR: "꼬리 후려치기",         nameEN: "Tail Swipe"),
        SpellEntry(id: 358385, nameKR: "산사태",                nameEN: "Landslide"),

        // Major cooldowns
        SpellEntry(id: 370537, nameKR: "정체",                  nameEN: "Stasis"),
        SpellEntry(id: 363534, nameKR: "되감기",                nameEN: "Rewind"),
        SpellEntry(id: 359816, nameKR: "꿈의 비행",             nameEN: "Dream Flight"),
        SpellEntry(id: 370553, nameKR: "시간 조정",             nameEN: "Tip the Scales"),
        SpellEntry(id: 390386, nameKR: "용의 격노",             nameEN: "Fury of the Aspects"),
    ]
}
