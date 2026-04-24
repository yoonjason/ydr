import Foundation
import os

@MainActor
final class MemoEditorViewModel: ObservableObject {

    // MARK: - State

    @Published var memoText: String = "" {
        didSet { guard !suppressChange else { return }; markDirty() }
    }

    @Published var fontSize: Int = 14 {
        didSet { guard !suppressChange else { return }; markDirty() }
    }

    @Published var fontColor: ColorPreset = .white {
        didSet { guard !suppressChange else { return }; markDirty() }
    }

    @Published var bgAlpha: Int = 60 {
        didSet { guard !suppressChange else { return }; markDirty() }
    }

    @Published var wowAddonsPath: String = "" {
        didSet {
            guard !suppressPersist else { return }
            persistWowAddonsPath()
            if !wowAddonsPath.isEmpty { loadMemo() }
        }
    }

    @Published private(set) var isSaved: Bool = true
    @Published private(set) var lastSaveResult: String?

    // MARK: - Derived

    var memoFilePath: String {
        wowAddonsPath.isEmpty ? "" : persistence.filePath(wowAddonsPath: wowAddonsPath)
    }

    // MARK: - Dependencies

    private let persistence: MemoPersistenceProtocol
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "MemoEditor")

    private var suppressPersist = false
    private var suppressChange = false

    // MARK: - Init

    init(persistence: MemoPersistenceProtocol = MemoPersistence()) {
        self.persistence = persistence
    }

    // MARK: - Lifecycle

    func onAppear() {
        suppressPersist = true
        defer { suppressPersist = false }
        if wowAddonsPath.isEmpty {
            wowAddonsPath = UserDefaults.standard.string(forKey: "wowAddonsPath") ?? ""
        }
        if !wowAddonsPath.isEmpty { loadMemo() }
    }

    // MARK: - Actions

    func save() {
        guard !wowAddonsPath.isEmpty else {
            lastSaveResult = "WoW AddOns 경로가 설정되어 있지 않습니다."
            return
        }
        let content = MemoContent(
            lines: memoText.components(separatedBy: "\n"),
            fontSize: fontSize,
            fontColor: fontColor,
            bgAlpha: bgAlpha
        )
        let addonsPath = wowAddonsPath
        Task { @MainActor in
            do {
                let path = try await Task.detached(priority: .utility) { [persistence] in
                    try persistence.save(content, to: addonsPath)
                }.value
                lastSaveResult = "저장 완료: \(path)"
                isSaved = true
            } catch {
                lastSaveResult = "저장 실패: \(error.localizedDescription)"
                logger.error("메모 저장 실패: \(error)")
            }
        }
    }

    // MARK: - Private

    private func loadMemo() {
        suppressChange = true
        defer { suppressChange = false }
        let loaded = persistence.load(from: wowAddonsPath) ?? MemoContent()
        memoText  = loaded.lines.joined(separator: "\n")
        fontSize  = loaded.fontSize
        fontColor = loaded.fontColor
        bgAlpha   = loaded.bgAlpha
        isSaved = true
        lastSaveResult = nil
    }

    private func markDirty() {
        isSaved = false
        lastSaveResult = nil
    }

    private func persistWowAddonsPath() {
        guard !wowAddonsPath.isEmpty else { return }
        UserDefaults.standard.set(wowAddonsPath, forKey: "wowAddonsPath")
    }
}
