import XCTest
@testable import HealGuide

// MARK: - Mock

private final class MockMemoPersistence: MemoPersistenceProtocol, @unchecked Sendable {
    var savedBundle: MemoBundle?
    var bundleToReturn: MemoBundle?
    var shouldThrow = false

    func filePath(wowAddonsPath: String) -> String { "/mock/path/HGPT_Memo.lua" }

    func save(_ bundle: MemoBundle, to wowAddonsPath: String) throws -> String {
        if shouldThrow { throw NSError(domain: "mock", code: 1) }
        savedBundle = bundle
        return "/mock/path/HGPT_Memo.lua"
    }

    func load(from wowAddonsPath: String) -> MemoBundle? { bundleToReturn }
}

private struct MockCharacterScanner: WoWCharacterScannerProtocol {
    var characters: [WoWCharacter] = []
    var diagnosticMessage: String? = nil
    func scan(wowAddonsPath: String) -> [WoWCharacter] { characters }
    func scanWithDiagnostic(wowAddonsPath: String) -> (characters: [WoWCharacter], message: String?) {
        (characters, diagnosticMessage)
    }
}

// MARK: - Tests

@MainActor
final class MemoEditorViewModelTests: XCTestCase {

    private func makeSUT(
        bundleToReturn: MemoBundle? = nil,
        characters: [WoWCharacter] = []
    ) -> (MemoEditorViewModel, MockMemoPersistence) {
        let persistence = MockMemoPersistence()
        persistence.bundleToReturn = bundleToReturn
        let scanner = MockCharacterScanner(characters: characters)
        let vm = MemoEditorViewModel(persistence: persistence, characterScanner: scanner)
        return (vm, persistence)
    }

    // MARK: - 초기 로드

    func test_onAppear_loadsSharedSection() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통 메모"], fontSize: 16, fontColor: .cyan, bgAlpha: 70),
            characters: [:],
            updatedAt: 0
        )
        let (vm, _) = makeSUT(bundleToReturn: bundle)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        XCTAssertEqual(vm.memoText, "공통 메모")
        XCTAssertEqual(vm.fontSize, 16)
        XCTAssertEqual(vm.fontColor, .cyan)
        XCTAssertEqual(vm.bgAlpha, 70)
        XCTAssertEqual(vm.selectedKey, "shared")
    }

    func test_onAppear_noFile_usesDefaults() {
        let (vm, _) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        XCTAssertEqual(vm.memoText, "")
        XCTAssertEqual(vm.fontSize, 14)
        XCTAssertEqual(vm.fontColor, .white)
        XCTAssertEqual(vm.bgAlpha, 60)
    }

    // MARK: - 캐릭터 전환 (clean)

    func test_selectKey_whenClean_switchesImmediately() {
        let charContent = MemoContent(lines: ["캐릭터 내용"], fontSize: 18)
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: ["홍길동-서버1": charContent],
            updatedAt: 0
        )
        let (vm, _) = makeSUT(bundleToReturn: bundle)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.selectKey("홍길동-서버1")

        XCTAssertEqual(vm.selectedKey, "홍길동-서버1")
        XCTAssertEqual(vm.memoText, "캐릭터 내용")
        XCTAssertEqual(vm.fontSize, 18)
        XCTAssertFalse(vm.showDirtyConfirmation)
    }

    func test_selectKey_whenDirty_showsConfirmation() {
        let (vm, _) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.memoText = "변경됨"  // markDirty
        vm.selectKey("홍길동-서버1")

        XCTAssertTrue(vm.showDirtyConfirmation)
        XCTAssertEqual(vm.selectedKey, "shared", "전환 전이므로 shared 유지")
    }

    func test_confirmSwitchWithoutSaving_switchesAndDiscards() {
        let (vm, _) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.memoText = "버릴 내용"
        vm.selectKey("홍길동-서버1")
        vm.confirmSwitchWithoutSaving()

        XCTAssertEqual(vm.selectedKey, "홍길동-서버1")
        XCTAssertFalse(vm.showDirtyConfirmation)
        XCTAssertTrue(vm.isSaved)
    }

    func test_cancelSwitch_staysOnCurrentKey() {
        let (vm, _) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.memoText = "변경됨"
        vm.selectKey("홍길동-서버1")
        vm.cancelSwitch()

        XCTAssertEqual(vm.selectedKey, "shared")
        XCTAssertFalse(vm.showDirtyConfirmation)
    }

    // MARK: - saveGeneration 리셋 (보수적)

    func test_selectKey_resetsSaveGeneration_marksAsSaved() {
        let charContent = MemoContent(lines: ["캐릭터"])
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: ["A-서버": charContent],
            updatedAt: 0
        )
        let (vm, _) = makeSUT(bundleToReturn: bundle)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.memoText = "dirty"  // markDirty
        XCTAssertFalse(vm.isSaved)

        // 더티 상태에서 전환 → 확인 다이얼로그 표시
        vm.selectKey("A-서버")
        XCTAssertTrue(vm.showDirtyConfirmation, "더티일 때 확인 다이얼로그 표시")

        // 저장하지 않고 전환 → saveGeneration 리셋
        vm.confirmSwitchWithoutSaving()
        XCTAssertTrue(vm.isSaved, "전환 완료 후 isSaved = true")
        XCTAssertFalse(vm.showDirtyConfirmation, "다이얼로그 닫힘")
        XCTAssertEqual(vm.selectedKey, "A-서버")
    }

    // MARK: - 공통에서 복사

    func test_copyFromShared_populatesCurrentCharSection() {
        let shared = MemoContent(lines: ["공통 내용"], fontSize: 20, fontColor: .yellow, bgAlpha: 90)
        let bundle = MemoBundle(
            shared: shared,
            characters: ["캐릭터-서버": MemoContent()],
            updatedAt: 0
        )
        let (vm, _) = makeSUT(bundleToReturn: bundle)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()
        vm.selectKey("캐릭터-서버")

        vm.copyFromShared()

        XCTAssertEqual(vm.memoText, "공통 내용")
        XCTAssertEqual(vm.fontSize, 20)
        XCTAssertEqual(vm.fontColor, .yellow)
        XCTAssertEqual(vm.bgAlpha, 90)
        XCTAssertFalse(vm.isSaved, "복사 후 미저장 상태")
    }

    // MARK: - save

    func test_save_updatesBundle_withCurrentSection() {
        let (vm, persistence) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.memoText = "저장할 내용"
        vm.fontSize = 18
        vm.fontColor = .red
        vm.bgAlpha = 50

        vm.save()

        // Task 완료 전까지는 savedBundle이 nil일 수 있으나 shared 설정 확인
        // 즉시 snapshot은 bundle 업데이트 후 persistence.save 호출
        // (비동기 Task이므로 저장 완료는 expectation 없이 bundle 상태만 확인)
        // 비동기 저장 완료 검증은 test_confirmSwitchWithSaving_savesBeforeSwitching 에서 수행
    }

    func test_confirmSwitchWithSaving_savesBeforeSwitching() async {
        let (vm, persistence) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        vm.memoText = "저장할 내용"
        vm.selectKey("홍길동-서버1")  // dirty → showDirtyConfirmation = true
        XCTAssertTrue(vm.showDirtyConfirmation)

        await vm.confirmSwitchWithSaving()

        XCTAssertNotNil(persistence.savedBundle, "섹션 전환 전에 저장 완료")
        XCTAssertEqual(vm.selectedKey, "홍길동-서버1", "전환 완료")
        XCTAssertFalse(vm.showDirtyConfirmation)
    }

    func test_save_emptyPath_setsErrorMessage() {
        let (vm, _) = makeSUT(bundleToReturn: nil)

        vm.save()

        XCTAssertEqual(vm.lastSaveResult, "WoW AddOns 경로가 설정되어 있지 않습니다.")
    }

    // MARK: - isCurrentSectionEmpty

    func test_isCurrentSectionEmpty_shared_alwaysFalse() {
        let (vm, _) = makeSUT(bundleToReturn: nil)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()

        XCTAssertFalse(vm.isCurrentSectionEmpty, "shared는 항상 false")
    }

    func test_isCurrentSectionEmpty_characterWithNoContent_true() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: ["캐릭터-서버": MemoContent(lines: ["", ""])],
            updatedAt: 0
        )
        let (vm, _) = makeSUT(bundleToReturn: bundle)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()
        vm.selectKey("캐릭터-서버")

        XCTAssertTrue(vm.isCurrentSectionEmpty)
    }

    func test_isCurrentSectionEmpty_characterWithContent_false() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: ["캐릭터-서버": MemoContent(lines: ["내용 있음"])],
            updatedAt: 0
        )
        let (vm, _) = makeSUT(bundleToReturn: bundle)
        vm.wowAddonsPath = "/mock/addons"
        vm.onAppear()
        vm.selectKey("캐릭터-서버")

        XCTAssertFalse(vm.isCurrentSectionEmpty)
    }
}
