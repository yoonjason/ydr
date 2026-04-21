import Foundation
import AppKit
import os

@MainActor
final class TacticalGuideEditorViewModel: ObservableObject {

    // MARK: - Input / State

    @Published var selectedDungeon: DungeonInfo? = DungeonInfo.currentSeason.first {
        didSet { rebuildBossList(); selectedBossIndex = 0 }
    }
    @Published private(set) var bossList: [BossTacticalGuide] = []
    @Published var selectedBossIndex: Int = 0 {
        didSet { rebuildEditableLines() }
    }

    // 현재 편집 중인 라인들 (복사본). 저장 버튼 눌러야 persist.
    @Published var editableLines: [EditableLine] = []
    @Published var lastActionResult: String?

    // MARK: - Dependencies

    private let persistence = TacticalGuidePersistence.shared
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "TacticalEditor")

    // MARK: - Lifecycle

    func onAppear() {
        rebuildBossList()
        rebuildEditableLines()
    }

    // MARK: - Derivations

    private func rebuildBossList() {
        guard let dungeon = selectedDungeon else {
            bossList = []
            return
        }
        bossList = TacticalGuideCatalog.bossGuides(forDungeonID: dungeon.id)
    }

    private func rebuildEditableLines() {
        guard !bossList.isEmpty,
              selectedBossIndex < bossList.count else {
            editableLines = []
            return
        }
        let boss = bossList[selectedBossIndex]
        editableLines = boss.lines.map { EditableLine(line: $0) }
    }

    // MARK: - Edit actions

    func addLine() {
        editableLines.append(EditableLine(
            line: TacticalLine(priority: .note, abilityName: "", action: "새 전술 — 내용을 입력하세요")
        ))
    }

    func deleteLine(id: UUID) {
        editableLines.removeAll { $0.id == id }
    }

    func moveLineUp(id: UUID) {
        guard let idx = editableLines.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        editableLines.swapAt(idx, idx - 1)
    }

    func moveLineDown(id: UUID) {
        guard let idx = editableLines.firstIndex(where: { $0.id == id }),
              idx < editableLines.count - 1 else { return }
        editableLines.swapAt(idx, idx + 1)
    }

    // MARK: - Persist

    /// 현재 편집 상태를 persistence 에 저장. 전체 파일 재작성 (다른 보스 편집 내역 유지).
    func saveCurrent() {
        guard let dungeon = selectedDungeon,
              !bossList.isEmpty,
              selectedBossIndex < bossList.count else {
            lastActionResult = "저장할 보스가 선택되지 않았습니다."
            return
        }
        let boss = bossList[selectedBossIndex]
        let lines = editableLines.map { $0.toTacticalLine() }

        // 기존 파일 로드 or 새 파일
        var file = persistence.load() ?? TacticalGuideCustomFile(
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        // 던전 엔트리 upsert
        let dungeonIdx = file.customizations.firstIndex { $0.dungeonID == dungeon.id }
        var dungeonEntry: DungeonCustomization
        if let idx = dungeonIdx {
            dungeonEntry = file.customizations[idx]
        } else {
            dungeonEntry = DungeonCustomization(dungeonID: dungeon.id, bosses: [])
        }

        // 보스 엔트리 upsert
        let bossIdx = dungeonEntry.bosses.firstIndex { $0.englishBossName == boss.englishBossName }
        let newBoss = BossCustomization(
            englishBossName: boss.englishBossName,
            koreanBossName:  boss.koreanBossName,
            lines:           lines
        )
        if let bIdx = bossIdx {
            dungeonEntry.bosses[bIdx] = newBoss
        } else {
            dungeonEntry.bosses.append(newBoss)
        }

        if let dIdx = dungeonIdx {
            file.customizations[dIdx] = dungeonEntry
        } else {
            file.customizations.append(dungeonEntry)
        }

        let ok = persistence.save(file)
        if ok {
            TacticalGuideCatalog.reloadCustom()
            rebuildBossList()
            // 저장한 보스를 선택 상태 유지
            if let newIdx = bossList.firstIndex(where: { $0.englishBossName == boss.englishBossName }) {
                selectedBossIndex = newIdx
            }
            lastActionResult = "저장 완료 — 재수집 시 자동 반영"
        } else {
            lastActionResult = "저장 실패"
        }
    }

    /// 편집을 버리고 저장된 상태로 되돌림.
    func revertCurrent() {
        rebuildEditableLines()
        lastActionResult = "저장된 상태로 되돌림"
    }
}

// MARK: - Editable wrapper

// UUID 로 각 라인 독립 추적 (같은 내용의 라인이 여러 개여도 구분 가능).
struct EditableLine: Identifiable, Equatable {
    let id: UUID = UUID()
    var priority: TacticalPriority
    var abilityName: String
    var action: String

    init(line: TacticalLine) {
        self.priority = line.priority
        self.abilityName = line.abilityName
        self.action = line.action
    }

    func toTacticalLine() -> TacticalLine {
        TacticalLine(priority: priority, abilityName: abilityName, action: action)
    }
}
