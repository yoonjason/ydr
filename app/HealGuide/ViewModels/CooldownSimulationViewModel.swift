import Foundation
import os

@MainActor
final class CooldownSimulationViewModel: ObservableObject {

    // MARK: - Input

    @Published var selectedSpec: HealerSpec = .discPriest {
        didSet { rebuildSpellList(); runSimulation() }
    }
    @Published var selectedDungeon: DungeonInfo? = DungeonInfo.currentSeason.first {
        didSet { runSimulation() }
    }
    @Published var cooldownSpellIDs: Set<Int> = [] {
        didSet { runSimulation() }
    }

    // MARK: - Output

    @Published private(set) var availableSpells: [HealerSpellRow] = []
    @Published private(set) var matchedEntry: HGPTRankerData?
    @Published private(set) var results: [SimulationResult] = []
    @Published private(set) var hasData: Bool = false

    // MARK: - Dependencies

    private let cacheService: RankerCacheService
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "CooldownSim")

    init(cacheService: RankerCacheService = RankerCacheService()) {
        self.cacheService = cacheService
    }

    func onAppear() {
        rebuildSpellList()
        runSimulation()
    }

    // MARK: - Actions

    func toggleCooldown(spellID: Int) {
        if cooldownSpellIDs.contains(spellID) {
            cooldownSpellIDs.remove(spellID)
        } else {
            cooldownSpellIDs.insert(spellID)
        }
    }

    func clearCooldowns() {
        cooldownSpellIDs.removeAll()
    }

    func setAllOnCooldown() {
        cooldownSpellIDs = Set(availableSpells.map(\.spellID))
    }

    // MARK: - Derivations

    private func rebuildSpellList() {
        let spellIDs = HealerSpellCategoryCatalog.knownSpellIDs(for: selectedSpec)
        availableSpells = spellIDs.compactMap { id -> HealerSpellRow? in
            guard let cat = HealerSpellCategoryCatalog.category(for: id, spec: selectedSpec) else { return nil }
            return HealerSpellRow(
                spellID: id,
                name: nameFromCache(spellID: id) ?? "Spell #\(id)",
                category: cat
            )
        }
        .sorted { $0.category.rawValue < $1.category.rawValue }
    }

    private func runSimulation() {
        guard let dungeon = selectedDungeon else {
            matchedEntry = nil
            results = []
            hasData = false
            return
        }
        // 캐시에서 (spec, dungeonID) 일치 엔트리 검색
        let entries = cacheService.loadAll()
        let found = entries.first { $0.meta.spec == selectedSpec.rawValue && $0.meta.dungeonID == dungeon.id }

        matchedEntry = found
        guard let entry = found else {
            results = []
            hasData = false
            return
        }
        hasData = true

        // 랭커 데이터 순회하며 시뮬
        var outcomes: [SimulationResult] = []
        for (encID, bossMap) in entry.encounterData.sorted(by: { $0.key < $1.key }) {
            for (bossSpellID, responses) in bossMap.sorted(by: { $0.key < $1.key }) {
                var skipped: [SimulationResult.Entry] = []
                var recommended: SimulationResult.Entry?
                for response in responses {
                    let spellName = entry.spellNames[response.spellID] ?? "Spell #\(response.spellID)"
                    let category = HealerSpellCategoryCatalog.category(for: response.spellID, spec: selectedSpec)
                    let item = SimulationResult.Entry(
                        spellID: response.spellID,
                        spellName: spellName,
                        category: category,
                        delay: response.delay,
                        quorum: response.quorum
                    )
                    if cooldownSpellIDs.contains(response.spellID) {
                        skipped.append(item)
                    } else if recommended == nil {
                        recommended = item
                    } else {
                        // 2순위 이후 사용 가능한 스킬 — '대안' 으로 분류
                        skipped.append(item)
                    }
                }
                outcomes.append(SimulationResult(
                    encounterID:   encID,
                    encounterName: entry.encounterNames[encID] ?? "Enc \(encID)",
                    bossSpellID:   bossSpellID,
                    bossSpellName: entry.spellNames[bossSpellID] ?? "Boss #\(bossSpellID)",
                    recommended:   recommended,
                    skipped:       skipped
                ))
            }
        }
        results = outcomes
    }

    // Blizzard 스킬 이름이 캐시에 있으면 사용, 없으면 nil.
    // 엔트리 로드 전에 호출되면 nil 반환 — spec 변경 시 matchedEntry 로부터 재구축.
    private func nameFromCache(spellID: Int) -> String? {
        matchedEntry?.spellNames[spellID]
    }
}

struct HealerSpellRow: Identifiable {
    let spellID: Int
    let name: String
    let category: HealerSpellCategory

    var id: Int { spellID }
}

struct SimulationResult: Identifiable {
    let encounterID: Int
    let encounterName: String
    let bossSpellID: Int
    let bossSpellName: String
    let recommended: Entry?
    let skipped: [Entry]

    var id: String { "\(encounterID)-\(bossSpellID)" }

    struct Entry: Identifiable {
        let spellID: Int
        let spellName: String
        let category: HealerSpellCategory?
        let delay: Double
        let quorum: String

        var id: Int { spellID }
    }
}
