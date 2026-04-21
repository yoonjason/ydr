import Foundation

// MARK: - Dungeon / Difficulty

struct DungeonInfo: Identifiable, Hashable {
    let id: Int       // WarcraftLogs encounter ID for the full-run characterRankings query
    let name: String
    let supportsNormalHeroic: Bool  // false = 쐐기 전용 (구 확장 재활용 던전)

    // TODO: Update this list each season.
    // IDs correspond to WarcraftLogs worldData.encounter(id:).characterRankings encounterId.
    static let currentSeason: [DungeonInfo] = [
        // 한밤(Midnight) 시즌 1 — 신규 던전 (일반/영웅/쐐기 모두 지원)
        DungeonInfo(id: 12805,  name: "윈드러너 첨탑 (Windrunner Spire)",          supportsNormalHeroic: true),
        DungeonInfo(id: 12811,  name: "마법학자의 정원 (Magisters' Terrace)",        supportsNormalHeroic: true),
        DungeonInfo(id: 12874,  name: "마이사라 동굴 (Maisara Caverns)",            supportsNormalHeroic: true),
        DungeonInfo(id: 12915,  name: "공결탑 제나스 (Nexus-Point Xenas)",          supportsNormalHeroic: true),
        // 한밤(Midnight) 시즌 1 — 구 확장 재활용 던전 (쐐기만 지원)
        DungeonInfo(id: 112526, name: "알게타르 대학 (Algeth'ar Academy)",          supportsNormalHeroic: false),
        DungeonInfo(id: 361753, name: "삼두정의 권좌 (Seat of the Triumvirate)",    supportsNormalHeroic: false),
        DungeonInfo(id: 61209,  name: "하늘탑 (Skyreach)",                         supportsNormalHeroic: false),
        DungeonInfo(id: 10658,  name: "사론의 구덩이 (Pit of Saron)",              supportsNormalHeroic: false),
    ]
}

enum RankerDifficulty: String, CaseIterable, Identifiable {
    case mythicPlus = "Mythic+"
    case heroic     = "Heroic"
    case normal     = "Normal"

    var id: String { rawValue }

    // Maps to WarcraftLogs difficulty parameter; nil = M+ (no single ID)
    var warcraftLogsID: Int? {
        switch self {
        case .mythicPlus: return nil
        case .heroic:     return 4
        case .normal:     return 3
        }
    }
}

enum TopNCount: Int, CaseIterable, Identifiable {
    case five   = 5
    case ten    = 10
    case twenty = 20

    var id: Int { rawValue }
    var displayName: String { "상위 \(rawValue)명" }
}

// MARK: - Talent Filter Config

struct TalentFilterConfig {
    let preset: TalentPreset?
    let talentString: String?
    let jaccardThreshold: Double   // 0.8 기본, "완화" 시 0.6
}

// MARK: - Ranker Parse (characterRankings 결과 1개)

struct RankerParse: Identifiable {
    let id: String           // "\(reportCode)-\(fightID)"
    let reportCode: String
    let fightID: Int
    let talentNodeIDs: Set<Int>
    let characterName: String
}

// MARK: - Boss → Heal 매핑 단위

struct BossHealPair {
    let encounterID: Int
    let bossSpellID: Int
    let healSpellID: Int
    let delaySeconds: Double
}

// MARK: - Welford 온라인 분산 누산기

struct WelfordAccumulator {
    private(set) var count: Int    = 0
    private(set) var mean: Double  = 0
    private(set) var m2: Double    = 0

    mutating func update(_ value: Double) {
        count += 1
        let delta  = value - mean
        mean      += delta / Double(count)
        let delta2 = value - mean
        m2        += delta * delta2
    }

    var variance: Double { count < 2 ? 0 : m2 / Double(count - 1) }
    var stddev:   Double { variance.squareRoot() }
}

// MARK: - 병합 결과 단위

struct RankerResponseEntry: Codable {
    let spellID: Int
    let delay:   Double
    let stddev:  Double
    let count:   Int
    let quorum:  String   // e.g. "8/10"
}

// MARK: - HGPT_RankerData (Lua 스키마 대응)

struct HGPTRankerDataMeta {
    let version:             Int
    let collectedAt:         String   // ISO8601 KST
    let region:              String
    let dungeonID:           Int
    let dungeonName:         String
    let difficulty:          String
    let spec:                String
    let rankersRequested:    Int
    let rankersUsed:         Int
    let talentFilterPreset:  String
    let talentFilterString:  String?  // nil = 미사용, 비어있지 않은 문자열 = 사용된 탤런트 스트링
    let talentFilterSimilarity: Double
}

extension HGPTRankerDataMeta: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, collectedAt, region, dungeonID, dungeonName, difficulty, spec,
             rankersRequested, rankersUsed, talentFilterPreset, talentFilterString, talentFilterSimilarity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version                = try c.decode(Int.self,    forKey: .version)
        collectedAt            = try c.decode(String.self, forKey: .collectedAt)
        region                 = try c.decode(String.self, forKey: .region)
        dungeonID              = try c.decode(Int.self,    forKey: .dungeonID)
        dungeonName            = try c.decode(String.self, forKey: .dungeonName)
        difficulty             = try c.decode(String.self, forKey: .difficulty)
        spec                   = try c.decode(String.self, forKey: .spec)
        rankersRequested       = try c.decode(Int.self,    forKey: .rankersRequested)
        rankersUsed            = try c.decode(Int.self,    forKey: .rankersUsed)
        talentFilterPreset     = try c.decode(String.self, forKey: .talentFilterPreset)
        talentFilterSimilarity = try c.decode(Double.self, forKey: .talentFilterSimilarity)
        // 역호환: 구 포맷은 Bool(true/false)로 저장 — 스트링 값 복원 불가이므로 nil로 폴백
        if let str = try? c.decode(String.self, forKey: .talentFilterString), !str.isEmpty {
            talentFilterString = str
        } else {
            talentFilterString = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version,               forKey: .version)
        try c.encode(collectedAt,           forKey: .collectedAt)
        try c.encode(region,                forKey: .region)
        try c.encode(dungeonID,             forKey: .dungeonID)
        try c.encode(dungeonName,           forKey: .dungeonName)
        try c.encode(difficulty,            forKey: .difficulty)
        try c.encode(spec,                  forKey: .spec)
        try c.encode(rankersRequested,      forKey: .rankersRequested)
        try c.encode(rankersUsed,           forKey: .rankersUsed)
        try c.encode(talentFilterPreset,    forKey: .talentFilterPreset)
        try c.encodeIfPresent(talentFilterString, forKey: .talentFilterString)
        try c.encode(talentFilterSimilarity, forKey: .talentFilterSimilarity)
    }
}

struct HGPTRankerData {
    let meta:          HGPTRankerDataMeta
    // [encounterID: [bossSpellID: [entries]]]
    let encounterData: [Int: [Int: [RankerResponseEntry]]]
    // Blizzard Journal Encounter API 로 해상한 한국어 이름. 없으면 애드온이 EJ_GetEncounterInfo 로 폴백.
    var encounterNames: [Int: String]
    // Phase 2: 힐러/보스 spellID → 한국어 스킬명 (Blizzard Spell API).
    var spellNames: [Int: String] = [:]
    // Phase 3: [encounterID: [bossSpellID: 한국어 기믹 설명]] (Blizzard Journal Encounter abilities).
    var abilityDescriptions: [Int: [Int: String]] = [:]
    // Phase 3b: [encounterID: [bossSpellID: [전술 라인]]] — 사용자 큐레이션 가이드 매칭 결과.
    var tacticalLines: [Int: [Int: [TacticalLine]]] = [:]
    // Phase 3b: [encounterID: [보스 전체 주의사항]] — abilityName 빈 라인 (shared tactics).
    var sharedTacticalLines: [Int: [TacticalLine]] = [:]
    // Phase 4: [encounterID: [bossSpellID: 한국어 스킬명]] — 애드온 이름 매칭 fallback 용.
    var bossSpellNames: [Int: [Int: String]] = [:]
}

extension HGPTRankerData: Codable {
    enum CodingKeys: String, CodingKey {
        case meta, encounterData, encounterNames, spellNames, abilityDescriptions, tacticalLines, sharedTacticalLines, bossSpellNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(HGPTRankerDataMeta.self, forKey: .meta)

        let stringKeyed = try container.decode(
            [String: [String: [RankerResponseEntry]]].self,
            forKey: .encounterData
        )
        var result: [Int: [Int: [RankerResponseEntry]]] = [:]
        for (encStr, bossMap) in stringKeyed {
            guard let encID = Int(encStr) else { continue }
            var innerMap: [Int: [RankerResponseEntry]] = [:]
            for (bossStr, responses) in bossMap {
                guard let bossID = Int(bossStr) else { continue }
                innerMap[bossID] = responses
            }
            result[encID] = innerMap
        }
        encounterData = result

        // 구 포맷 역호환: encounterNames 없으면 빈 딕셔너리로 폴백
        let rawNames = (try? container.decode([String: String].self, forKey: .encounterNames)) ?? [:]
        encounterNames = rawNames.reduce(into: [:]) { acc, pair in
            if let id = Int(pair.key) { acc[id] = pair.value }
        }

        // Phase 2 역호환: spellNames 없으면 빈 맵
        let rawSpellNames = (try? container.decode([String: String].self, forKey: .spellNames)) ?? [:]
        spellNames = rawSpellNames.reduce(into: [:]) { acc, pair in
            if let id = Int(pair.key) { acc[id] = pair.value }
        }

        // Phase 3 역호환: abilityDescriptions 없으면 빈 맵
        let rawAbilities = (try? container.decode([String: [String: String]].self, forKey: .abilityDescriptions)) ?? [:]
        var abilities: [Int: [Int: String]] = [:]
        for (encStr, bossMap) in rawAbilities {
            guard let encID = Int(encStr) else { continue }
            var inner: [Int: String] = [:]
            for (bossStr, desc) in bossMap {
                if let bossID = Int(bossStr) { inner[bossID] = desc }
            }
            abilities[encID] = inner
        }
        abilityDescriptions = abilities

        // Phase 3b 역호환: tacticalLines 없으면 빈 맵
        let rawTactics = (try? container.decode([String: [String: [TacticalLine]]].self, forKey: .tacticalLines)) ?? [:]
        var tactics: [Int: [Int: [TacticalLine]]] = [:]
        for (encStr, bossMap) in rawTactics {
            guard let encID = Int(encStr) else { continue }
            var inner: [Int: [TacticalLine]] = [:]
            for (bossStr, lines) in bossMap {
                if let bossID = Int(bossStr) { inner[bossID] = lines }
            }
            tactics[encID] = inner
        }
        tacticalLines = tactics

        // Phase 3b 역호환: sharedTacticalLines 없으면 빈 맵
        let rawShared = (try? container.decode([String: [TacticalLine]].self, forKey: .sharedTacticalLines)) ?? [:]
        sharedTacticalLines = rawShared.reduce(into: [:]) { acc, pair in
            if let id = Int(pair.key) { acc[id] = pair.value }
        }

        // Phase 4 역호환: bossSpellNames 없으면 빈 맵
        let rawBossSpellNames = (try? container.decode([String: [String: String]].self, forKey: .bossSpellNames)) ?? [:]
        var bossNames: [Int: [Int: String]] = [:]
        for (encStr, bossMap) in rawBossSpellNames {
            guard let encID = Int(encStr) else { continue }
            var inner: [Int: String] = [:]
            for (bossStr, name) in bossMap {
                if let bossID = Int(bossStr) { inner[bossID] = name }
            }
            bossNames[encID] = inner
        }
        bossSpellNames = bossNames
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meta, forKey: .meta)

        var stringKeyed: [String: [String: [RankerResponseEntry]]] = [:]
        for (encID, bossMap) in encounterData {
            var innerMap: [String: [RankerResponseEntry]] = [:]
            for (bossID, responses) in bossMap {
                innerMap[String(bossID)] = responses
            }
            stringKeyed[String(encID)] = innerMap
        }
        try container.encode(stringKeyed, forKey: .encounterData)

        // NIT-2: 빈 맵은 직렬화 스킵. decode 측 try? + 빈 맵 폴백이 동일하게 동작하므로 역호환 유지.
        if !encounterNames.isEmpty {
            let stringNames = encounterNames.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
            try container.encode(stringNames, forKey: .encounterNames)
        }
        if !spellNames.isEmpty {
            let stringSpellNames = spellNames.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
            try container.encode(stringSpellNames, forKey: .spellNames)
        }
        if !abilityDescriptions.isEmpty {
            var stringAbilities: [String: [String: String]] = [:]
            for (encID, bossMap) in abilityDescriptions {
                var inner: [String: String] = [:]
                for (bossID, desc) in bossMap {
                    inner[String(bossID)] = desc
                }
                stringAbilities[String(encID)] = inner
            }
            try container.encode(stringAbilities, forKey: .abilityDescriptions)
        }
        if !tacticalLines.isEmpty {
            var stringTactics: [String: [String: [TacticalLine]]] = [:]
            for (encID, bossMap) in tacticalLines {
                var inner: [String: [TacticalLine]] = [:]
                for (bossID, lines) in bossMap {
                    inner[String(bossID)] = lines
                }
                stringTactics[String(encID)] = inner
            }
            try container.encode(stringTactics, forKey: .tacticalLines)
        }
        if !sharedTacticalLines.isEmpty {
            let stringShared = sharedTacticalLines.reduce(into: [String: [TacticalLine]]()) {
                $0[String($1.key)] = $1.value
            }
            try container.encode(stringShared, forKey: .sharedTacticalLines)
        }
        if !bossSpellNames.isEmpty {
            var stringBossSpellNames: [String: [String: String]] = [:]
            for (encID, bossMap) in bossSpellNames {
                var inner: [String: String] = [:]
                for (bossID, name) in bossMap {
                    inner[String(bossID)] = name
                }
                stringBossSpellNames[String(encID)] = inner
            }
            try container.encode(stringBossSpellNames, forKey: .bossSpellNames)
        }
    }
}

// MARK: - 진행 상태

struct RankerCollectionProgress {
    let total:       Int
    let completed:   Int
    let currentName: String
}

// MARK: - 미리보기 결과

struct RankerPreviewResult {
    let parsesCollected: Int
    let parsesFiltered:  Int
    struct BossEntry {
        let encounterID:  Int
        let bossSpellID:  Int
        let mappingCount: Int
        // Blizzard API 해상 이후 채워짐. 자격증명 미설정 또는 조회 실패 시 nil.
        var encounterName: String? = nil
        var bossSpellName: String? = nil

        // encounterID + bossSpellID 조합을 SwiftUI ForEach ID로 사용 (보스 스펠이
        // 여러 encounter에 걸쳐 재사용될 수 있어 bossSpellID 단독은 충돌 가능).
        var compositeID: String { "\(encounterID)-\(bossSpellID)" }
    }
    let bossEntries:           [BossEntry]
    let highVarianceWarnings:  [String]   // "encID-bossID: stddev N.N"
}
