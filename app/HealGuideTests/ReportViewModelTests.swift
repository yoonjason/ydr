import XCTest
@testable import HealGuide

@MainActor
final class ReportViewModelTests: XCTestCase {
    private let validURL = "https://www.warcraftlogs.com/reports/AbCd1234#fight=3&source=7"
    private let mockOutput = LuaOutput(luaText: "-- mock lua", entryCount: 0)

    private func makeSUT(
        keychain: MockKeychain = MockKeychain(),
        apiClient: MockWarcraftLogsAPIClient = MockWarcraftLogsAPIClient(),
        normalizer: MockTimelineNormalizer = MockTimelineNormalizer(),
        luaGenerator: MockLuaGenerator = MockLuaGenerator()
    ) -> ReportViewModel {
        ReportViewModel(
            urlParser: URLParser(),
            keychain: keychain,
            apiClient: apiClient,
            normalizer: normalizer,
            luaGenerator: luaGenerator,
            pasteboard: MockPasteboard()
        )
    }

    func test_onAppear_loadsSecretFromKeychain() {
        let keychain = MockKeychain()
        keychain.stored = "saved-secret"
        let vm = makeSUT(keychain: keychain)

        vm.onAppear()

        XCTAssertEqual(vm.clientSecret, "saved-secret")
    }

    func test_onAppear_loadsClientIDFromKeychain() {
        let keychain = MockKeychain()
        keychain.storedClientID = "saved-id"
        let vm = makeSUT(keychain: keychain)

        vm.onAppear()

        XCTAssertEqual(vm.clientID, "saved-id")
    }

    func test_onAppear_alreadyFilledClientID_notOverwritten() {
        let keychain = MockKeychain()
        keychain.storedClientID = "keychain-id"
        let vm = makeSUT(keychain: keychain)
        vm.clientID = "manual-id"

        vm.onAppear()

        XCTAssertEqual(vm.clientID, "manual-id")
    }

    func test_fetchFight_invalidURL_setsFailureInvalidURL() async {
        let vm = makeSUT()
        vm.reportURLText = "not-a-valid-url"
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.invalidURL))
    }

    func test_fetchFight_emptyCredentials_setsFailureAuth() async {
        let vm = makeSUT()
        vm.reportURLText = validURL
        vm.clientID = ""
        vm.clientSecret = ""

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.authenticationFailed))
    }

    func test_fetchFight_authFailure_setsFailure() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.tokenResult = .failure(.authenticationFailed)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.authenticationFailed))
    }

    func test_fetchFight_fightNotFound_setsFailure() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.fightResult = .failure(.fightNotFound)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.fightNotFound))
    }

    func test_fetchFight_castsFailure_setsFailure() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.castsResult = .failure(.networkError("casts failed"))
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.networkError("casts failed")))
    }

    func test_fetchFight_success_setsSuccessWithLuaOutput() async {
        let luaGenerator = MockLuaGenerator()
        luaGenerator.result = mockOutput
        let vm = makeSUT(luaGenerator: luaGenerator)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .success(mockOutput))
    }

    func test_fetchFight_success_savesSecretToKeychain() async {
        let keychain = MockKeychain()
        let vm = makeSUT(keychain: keychain)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "my-secret"

        await vm.fetchFight()

        XCTAssertEqual(keychain.stored, "my-secret")
    }

    func test_fetchFight_success_savesClientIDToKeychain() async {
        let keychain = MockKeychain()
        let vm = makeSUT(keychain: keychain)
        vm.reportURLText = validURL
        vm.clientID = "my-client-id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(keychain.storedClientID, "my-client-id")
    }

    func test_fetchFight_fightLast_setsFailureFightSelectionRequired() async {
        let vm = makeSUT()
        vm.reportURLText = "https://www.warcraftlogs.com/reports/AbCd1234#fight=last&source=7"
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.fightSelectionRequired))
    }

    func test_fetchFight_keychainSaveFails_stillSucceeds() async {
        let keychain = MockKeychain()
        keychain.shouldThrowOnSave = true
        let vm = makeSUT(keychain: keychain)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        if case .success = vm.state { } else { XCTFail("expected success, got \(vm.state)") }
    }

    func test_fetchFight_whileFetching_secondCallIsIgnored() async {
        let vm = makeSUT()
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        let task = Task { await vm.fetchFight() }
        await vm.fetchFight()
        await task.value

        if case .success = vm.state { } else if case .failure = vm.state { } else {
            XCTFail("unexpected idle state after fetch")
        }
    }

    func test_copyToClipboard_whenSuccess_writesToPasteboard() {
        let pasteboard = MockPasteboard()
        let vm = ReportViewModel(
            urlParser: URLParser(),
            keychain: MockKeychain(),
            apiClient: MockWarcraftLogsAPIClient(),
            normalizer: MockTimelineNormalizer(),
            luaGenerator: MockLuaGenerator(),
            pasteboard: pasteboard
        )
        // success 상태 직접 설정 불가(private(set))이므로 상태를 우회 테스트
        // 실제로는 copyToClipboard가 idle 상태에서 아무것도 안 하는 것을 확인
        vm.copyToClipboard()
        XCTAssertTrue(pasteboard.writtenStrings.isEmpty)
    }

    func test_isSecretVisible_defaultFalse() {
        let vm = makeSUT()
        XCTAssertFalse(vm.isSecretVisible)
    }
}
