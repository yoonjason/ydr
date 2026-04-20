import Foundation

// MARK: - Dungeon / Difficulty

struct DungeonInfo: Identifiable, Hashable {
    let id: Int       // WarcraftLogs encounter ID for the full-run characterRankings query
    let name: String

    // TODO: Update this list each season.
    // IDs correspond to WarcraftLogs worldData.encounter(id:).characterRankings encounterId.
    static let currentSeason: [DungeonInfo] = [
        // TWW Season 2
        DungeonInfo(id: 13161, name: "신병의 요새 (The Rookery)"),
        DungeonInfo(id: 13157, name: "신더브루 목장 (Cinderbrew Meadery)"),
        DungeonInfo(id: 13230, name: "작전명: 수문 (Operation: Floodgate)"),
        DungeonInfo(id: 13228, name: "성스러운 불꽃 수도원 (Priory of Sacred Flame)"),
        DungeonInfo(id: 61458, name: "금광!! (The Motherlode!!)"),
        DungeonInfo(id: 61565, name: "메카곤: 작업장 (Mechagon: Workshop)"),
        DungeonInfo(id: 12648, name: "어둠꽃 열곡 (Darkflame Cleft)"),
        DungeonInfo(id: 61691, name: "고통의 전당 (Theater of Pain)"),
        // TWW Season 1 (for historical data)
        DungeonInfo(id: 12660, name: "아라카라, 메아리의 도시 (Ara-Kara)"),
        DungeonInfo(id: 12669, name: "실의 도시 (City of Threads)"),
        DungeonInfo(id: 60673, name: "그림 배톨 (Grim Batol)"),
        DungeonInfo(id: 2290,  name: "티르나 시크의 안개 (Mists of Tirna Scithe)"),
        DungeonInfo(id: 12662, name: "여명의 땅 (The Dawnbreaker)"),
        DungeonInfo(id: 12652, name: "석실 (The Stonevault)"),
        DungeonInfo(id: 61440, name: "보랄러스 공방전 (Siege of Boralus)"),
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
