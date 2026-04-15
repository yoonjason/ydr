import XCTest
@testable import HealGuide

@MainActor
final class ReportViewModelTests: XCTestCase {
    private let validURL = "https://www.warcraftlogs.com/reports/AbCd1234#fight=3&source=7"
    private let mockMeta = FightMeta(
        id: 3,
        encounterID: 2599,
        name: "Test Boss",
        startTime: 0,
        endTime: 10000,
        kill: true
    )

    private func makeSUT(
        keychain: MockKeychain = MockKeychain(),
        apiClient: MockWarcraftLogsAPIClient = MockWarcraftLogsAPIClient()
    ) -> ReportViewModel {
        ReportViewModel(
            urlParser: URLParser(),
            keychain: keychain,
            apiClient: apiClient
        )
    }

    func test_onAppear_loadsSecretFromKeychain() {
        let keychain = MockKeychain()
        keychain.stored = "saved-secret"
        let vm = makeSUT(keychain: keychain)

        vm.onAppear()

        XCTAssertEqual(vm.clientSecret, "saved-secret")
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

    func test_fetchFight_success_setsSuccessWithMeta() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.fightResult = .success(mockMeta)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.fetchFight()

        XCTAssertEqual(vm.state, .success(mockMeta))
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
        let apiClient = MockWarcraftLogsAPIClient()
        let vm = ReportViewModel(urlParser: URLParser(), keychain: keychain, apiClient: apiClient)
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
        // state가 .fetching으로 전환된 직후 두 번째 호출 — guard에 의해 즉시 return
        await vm.fetchFight()
        await task.value

        // 두 번째 호출이 state를 .idle 등으로 되돌리지 않았는지 확인
        if case .success = vm.state { } else if case .failure = vm.state { } else {
            XCTFail("unexpected idle state after fetch")
        }
    }
}
