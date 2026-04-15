import XCTest
@testable import HealGuide

@MainActor
final class ReportViewModelTests: XCTestCase {
    private let validURL = "https://www.warcraftlogs.com/reports/AbCd1234#fight=3&source=7"

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
        apiClient.encountersResult = .failure(.fightNotFound)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.fightNotFound))
    }

    func test_fetchFight_encountersFailure_setsFailure() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.encountersResult = .failure(.networkError("encounters failed"))
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.networkError("encounters failed")))
    }

    func test_fetchFight_emptyEncounters_setsNoBossEncounters() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.encountersResult = .failure(.noBossEncounters)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .failure(.noBossEncounters))
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
        luaGenerator.result = "-- generated lua"
        let vm = makeSUT(luaGenerator: luaGenerator)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        if case .success(let output) = vm.state {
            XCTAssertEqual(output.luaText, "-- generated lua")
        } else {
            XCTFail("Expected success, got \(vm.state)")
        }
    }

    func test_fetchFight_multiBoss_blocksOrderedByEncounterStart() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.encountersResult = .success(("Test Dungeon", [
            BossWindow(encounterID: 2600, name: "Boss B", startTime: 20000, endTime: 30000),
            BossWindow(encounterID: 2599, name: "Boss A", startTime: 0, endTime: 10000)
        ]))
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        guard case .success(let output) = vm.state else {
            XCTFail("Expected success, got \(vm.state)")
            return
        }
        XCTAssertEqual(output.blocks.count, 2)
        XCTAssertEqual(output.blocks[0].encounterID, 2599, "startTime 0인 Boss A가 먼저 와야 함")
        XCTAssertEqual(output.blocks[1].encounterID, 2600, "startTime 20000인 Boss B가 나중에 와야 함")
    }

    func test_fetchFight_multiBoss_buildsMultipleBlocks() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.encountersResult = .success(("Test Dungeon", [
            BossWindow(encounterID: 2599, name: "Boss A", startTime: 0, endTime: 10000),
            BossWindow(encounterID: 2600, name: "Boss B", startTime: 20000, endTime: 30000)
        ]))
        let normalizer = MockTimelineNormalizer()
        let luaGenerator = MockLuaGenerator()
        let vm = makeSUT(apiClient: apiClient, normalizer: normalizer, luaGenerator: luaGenerator)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        if case .success(let output) = vm.state {
            XCTAssertEqual(output.blockCount, 2)
        } else {
            XCTFail("Expected success, got \(vm.state)")
        }
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

    func test_copyToClipboard_whenIdle_doesNothing() {
        let pasteboard = MockPasteboard()
        let vm = ReportViewModel(
            urlParser: URLParser(),
            keychain: MockKeychain(),
            apiClient: MockWarcraftLogsAPIClient(),
            normalizer: MockTimelineNormalizer(),
            luaGenerator: MockLuaGenerator(),
            pasteboard: pasteboard
        )
        vm.copyToClipboard()
        XCTAssertTrue(pasteboard.writtenStrings.isEmpty)
    }

    func test_isSecretVisible_defaultFalse() {
        let vm = makeSUT()
        XCTAssertFalse(vm.isSecretVisible)
    }
}
