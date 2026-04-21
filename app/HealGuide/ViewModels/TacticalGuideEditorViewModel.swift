import Foundation
import AppKit
import UniformTypeIdentifiers
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

    // MARK: - Export / Import

    /// 현재 저장된 커스텀 파일을 사용자 지정 경로에 복사. 없으면 빈 파일 export.
    func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HealGuide_TacticalGuide_\(shortDate()).json"
        panel.message = "전술 가이드 커스텀 JSON 을 저장할 위치를 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let source = persistence.load() ?? TacticalGuideCustomFile(
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        if persistence.save(source, to: url) {
            lastActionResult = "Export 완료: \(url.lastPathComponent)"
        } else {
            lastActionResult = "Export 실패"
        }
    }

    /// 외부 JSON 파일 선택 → 현재 커스텀 파일과 병합 (같은 dungeonID+boss 는 import 가 교체).
    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "전술 가이드 커스텀 JSON 파일을 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let imported = persistence.load(from: url) else {
            lastActionResult = "Import 실패 — JSON 파싱 오류"
            return
        }

        // 기존 파일과 병합
        var current = persistence.load() ?? TacticalGuideCustomFile(
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        var mergedCount = 0
        for dungeonIn in imported.customizations {
            let dIdx = current.customizations.firstIndex { $0.dungeonID == dungeonIn.dungeonID }
            var entry: DungeonCustomization
            if let idx = dIdx {
                entry = current.customizations[idx]
            } else {
                entry = DungeonCustomization(dungeonID: dungeonIn.dungeonID, bosses: [])
            }
            for bossIn in dungeonIn.bosses {
                let bIdx = entry.bosses.firstIndex { $0.englishBossName == bossIn.englishBossName }
                if let i = bIdx {
                    entry.bosses[i] = bossIn
                } else {
                    entry.bosses.append(bossIn)
                }
                mergedCount += 1
            }
            if let idx = dIdx {
                current.customizations[idx] = entry
            } else {
                current.customizations.append(entry)
            }
        }

        if persistence.save(current) {
            TacticalGuideCatalog.reloadCustom()
            rebuildBossList()
            rebuildEditableLines()
            lastActionResult = "Import 완료 — \(mergedCount)개 보스 병합"
        } else {
            lastActionResult = "Import 병합 후 저장 실패"
        }
    }

    private func shortDate() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmm"
        return fmt.string(from: Date())
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
