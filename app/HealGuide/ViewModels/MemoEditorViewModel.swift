import Foundation
import os

@MainActor
final class MemoEditorViewModel: ObservableObject {

    // MARK: - 편집 상태

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

    // MARK: - 캐릭터 선택

    @Published private(set) var selectedKey: String = "shared"
    @Published private(set) var availableCharacters: [WoWCharacter] = []

    // MARK: - 경로 / 저장 상태

    @Published var wowAddonsPath: String = "" {
        didSet {
            guard !suppressPersist else { return }
            persistWowAddonsPath()
            if !wowAddonsPath.isEmpty {
                loadBundle()
                refreshCharacters()
            }
        }
    }

    @Published private(set) var isSaved: Bool = true
    @Published private(set) var lastSaveResult: String?
    @Published private(set) var lastScanMessage: String?

    // MARK: - Dirty 전환 확인 다이얼로그

    @Published var showDirtyConfirmation: Bool = false
    private var pendingKey: String?

    // MARK: - Derived

    var memoFilePath: String {
        wowAddonsPath.isEmpty ? "" : persistence.filePath(wowAddonsPath: wowAddonsPath)
    }

    var isCurrentSectionEmpty: Bool {
        guard selectedKey != "shared" else { return false }
        let c = bundle.characters[selectedKey]
        return c == nil || (c!.lines.allSatisfy { $0.isEmpty })
    }

    // MARK: - 의존성

    private let persistence: MemoPersistenceProtocol
    private let characterScanner: WoWCharacterScannerProtocol
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "MemoEditor")

    private var bundle: MemoBundle = MemoBundle()
    private var suppressPersist = false
    private var suppressChange = false
    private var saveGeneration: Int = 0

    // MARK: - Init

    init(
        persistence: MemoPersistenceProtocol = MemoPersistence(),
        characterScanner: WoWCharacterScannerProtocol = WoWCharacterScanner()
    ) {
        self.persistence = persistence
        self.characterScanner = characterScanner
    }

    // MARK: - Lifecycle

    func onAppear() {
        suppressPersist = true
        defer { suppressPersist = false }
        if wowAddonsPath.isEmpty {
            wowAddonsPath = UserDefaults.standard.string(forKey: "wowAddonsPath") ?? ""
        }
        if !wowAddonsPath.isEmpty {
            loadBundle()
            refreshCharacters()
        }
    }

    // MARK: - 캐릭터 전환

    func selectKey(_ key: String) {
        guard key != selectedKey else { return }
        if !isSaved {
            pendingKey = key
            showDirtyConfirmation = true
            return
        }
        applySelectedKey(key)
    }

    func confirmSwitchWithSaving() async {
        guard let key = pendingKey else { return }
        pendingKey = nil
        showDirtyConfirmation = false
        if !wowAddonsPath.isEmpty {
            let (bundleToSave, addonsPath) = prepareBundle()
            do {
                let path = try await Task.detached(priority: .utility) { [persistence] in
                    try persistence.save(bundleToSave, to: addonsPath)
                }.value
                lastSaveResult = "저장 완료: \(path)"
                isSaved = true
            } catch {
                lastSaveResult = "저장 실패: \(error.localizedDescription)"
                logger.error("메모 저장 실패: \(error)")
            }
        }
        applySelectedKey(key)
    }

    func confirmSwitchWithoutSaving() {
        guard let key = pendingKey else { return }
        pendingKey = nil
        showDirtyConfirmation = false
        applySelectedKey(key)
    }

    func cancelSwitch() {
        pendingKey = nil
        showDirtyConfirmation = false
    }

    // MARK: - 캐릭터 목록 새로고침

    func refreshCharacters() {
        guard !wowAddonsPath.isEmpty else { return }
        let result = characterScanner.scanWithDiagnostic(wowAddonsPath: wowAddonsPath)
        availableCharacters = result.characters
        lastScanMessage = result.message
    }

    // MARK: - 공통에서 복사

    func copyFromShared() {
        guard selectedKey != "shared" else { return }
        let shared = bundle.shared
        suppressChange = true
        memoText  = shared.lines.joined(separator: "\n")
        fontSize  = shared.fontSize
        fontColor = shared.fontColor
        bgAlpha   = shared.bgAlpha
        suppressChange = false
        markDirty()
    }

    // MARK: - 저장

    func save() {
        guard !wowAddonsPath.isEmpty else {
            lastSaveResult = "WoW AddOns 경로가 설정되어 있지 않습니다."
            return
        }
        let snapshot = saveGeneration
        let (bundleToSave, addonsPath) = prepareBundle()
        Task { @MainActor in
            do {
                let path = try await Task.detached(priority: .utility) { [persistence] in
                    try persistence.save(bundleToSave, to: addonsPath)
                }.value
                if self.saveGeneration == snapshot {
                    self.lastSaveResult = "저장 완료: \(path)"
                    self.isSaved = true
                }
            } catch {
                self.lastSaveResult = "저장 실패: \(error.localizedDescription)"
                self.logger.error("메모 저장 실패: \(error)")
            }
        }
    }

    // MARK: - Private: 저장 번들 구성

    // UI 상태로 bundle 을 업데이트하고 (side effect), 저장용 복사본과 경로를 반환.
    private func prepareBundle() -> (MemoBundle, String) {
        let now = Int(Date().timeIntervalSince1970)
        let content = MemoContent(
            lines: memoText.components(separatedBy: "\n"),
            fontSize: fontSize,
            fontColor: fontColor,
            bgAlpha: bgAlpha,
            updatedAt: now
        )
        var updatedBundle = bundle
        if selectedKey == "shared" {
            updatedBundle.shared = content
        } else {
            updatedBundle.characters[selectedKey] = content
        }
        updatedBundle.updatedAt = now
        bundle = updatedBundle
        return (updatedBundle, wowAddonsPath)
    }

    // MARK: - Private

    private func applySelectedKey(_ key: String) {
        selectedKey = key
        saveGeneration = 0  // 보수적: 섹션 전환 시 리셋
        loadCurrentSection()
    }

    private func loadBundle() {
        bundle = persistence.load(from: wowAddonsPath) ?? MemoBundle()
        loadCurrentSection()
        isSaved = true
        lastSaveResult = nil
    }

    private func loadCurrentSection() {
        suppressChange = true
        defer { suppressChange = false }
        let content = currentContent()
        memoText  = content.lines.joined(separator: "\n")
        fontSize  = content.fontSize
        fontColor = content.fontColor
        bgAlpha   = content.bgAlpha
        isSaved = true
        lastSaveResult = nil
    }

    private func currentContent() -> MemoContent {
        if selectedKey == "shared" { return bundle.shared }
        return bundle.characters[selectedKey] ?? MemoContent()
    }

    private func markDirty() {
        saveGeneration += 1
        isSaved = false
        lastSaveResult = nil
    }

    private func persistWowAddonsPath() {
        guard !wowAddonsPath.isEmpty else { return }
        UserDefaults.standard.set(wowAddonsPath, forKey: "wowAddonsPath")
    }
}
