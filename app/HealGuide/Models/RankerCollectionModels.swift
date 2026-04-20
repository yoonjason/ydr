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

struct HGPTRankerDataMeta: Codable {
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
    let talentFilterString:  Bool
    let talentFilterSimilarity: Double
}

struct HGPTRankerData {
    let meta:          HGPTRankerDataMeta
    // [encounterID: [bossSpellID: [entries]]]
    let encounterData: [Int: [Int: [RankerResponseEntry]]]
}

extension HGPTRankerData: Codable {
    enum CodingKeys: String, CodingKey {
        case meta, encounterData
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
    }
    let bossEntries:           [BossEntry]
    let highVarianceWarnings:  [String]   // "encID-bossID: stddev N.N"
}
