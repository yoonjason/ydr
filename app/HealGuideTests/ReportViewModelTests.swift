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

    // 힐러 자동 선택(URL source 일치) → 기본적으로 spellSelection 단계까지 진행되게 하는 헬퍼
    private func makeClientWithMatchingHealer(sourceID: Int = 7) -> MockWarcraftLogsAPIClient {
        let client = MockWarcraftLogsAPIClient()
        client.playerDetailsResult = .success([
            HealerCandidate(id: sourceID, name: "TestPriest", className: "Priest", specName: "Discipline", server: nil)
        ])
        return client
    }

    // MARK: - onAppear

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

    // MARK: - detectHealers 실패 케이스

    func test_detectHealers_invalidURL_setsFailureInvalidURL() async {
        let vm = makeSUT()
        vm.reportURLText = "not-a-valid-url"
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .failure(let e) = vm.state {
            XCTAssertEqual(e, .invalidURL)
        } else {
            XCTFail("expected .failure(.invalidURL)")
        }
    }

    func test_detectHealers_emptyCredentials_setsFailureAuth() async {
        let vm = makeSUT()
        vm.reportURLText = validURL
        vm.clientID = ""
        vm.clientSecret = ""

        await vm.detectHealers()

        if case .failure(let e) = vm.state {
            XCTAssertEqual(e, .authenticationFailed)
        } else {
            XCTFail("expected failure authenticationFailed")
        }
    }

    func test_detectHealers_authFailure_setsFailure() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.tokenResult = .failure(.authenticationFailed)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .failure(let e) = vm.state {
            XCTAssertEqual(e, .authenticationFailed)
        } else {
            XCTFail("expected failure authenticationFailed")
        }
    }

    func test_detectHealers_noHealers_setsFailureNoHealers() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.playerDetailsResult = .success([])
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .failure(let e) = vm.state {
            XCTAssertEqual(e, .noHealers)
        } else {
            XCTFail("expected .noHealers")
        }
    }

    // MARK: - detectHealers 성공 케이스

    func test_detectHealers_urlSourceMatches_advancesToSpellSelection() async {
        let apiClient = makeClientWithMatchingHealer(sourceID: 7)
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .spellSelection(let healer) = vm.state {
            XCTAssertEqual(healer.id, 7)
            XCTAssertFalse(vm.selectedSpellIDs.isEmpty)
        } else {
            XCTFail("expected .spellSelection, got \(vm.state)")
        }
    }

    func test_detectHealers_urlSourceNotMatches_advancesToHealerSelection() async {
        let apiClient = MockWarcraftLogsAPIClient()
        apiClient.playerDetailsResult = .success([
            HealerCandidate(id: 999, name: "Other", className: "Priest", specName: "Discipline", server: nil)
        ])
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL  // source=7
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .healerSelection(let healers, _) = vm.state {
            XCTAssertEqual(healers.count, 1)
            XCTAssertEqual(vm.selectedHealerID, 999)
        } else {
            XCTFail("expected .healerSelection")
        }
    }

    // MARK: - generate 플로우

    func test_generate_afterSpellSelection_setsSuccess() async {
        let luaGenerator = MockLuaGenerator()
        luaGenerator.result = "-- generated lua"
        let apiClient = makeClientWithMatchingHealer(sourceID: 7)
        let vm = makeSUT(apiClient: apiClient, luaGenerator: luaGenerator)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()  // advances to spellSelection
        await vm.generate()

        if case .success(let output, _) = vm.state {
            XCTAssertEqual(output.luaText, "-- generated lua")
        } else {
            XCTFail("expected success, got \(vm.state)")
        }
    }

    func test_generate_castsFailure_setsFailure() async {
        let apiClient = makeClientWithMatchingHealer(sourceID: 7)
        apiClient.castsResult = .failure(.networkError("casts failed"))
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()
        await vm.generate()

        if case .failure(let e) = vm.state {
            XCTAssertEqual(e, .networkError("casts failed"))
        } else {
            XCTFail("expected failure")
        }
    }

    func test_generate_uncheckAll_blocksHaveNoReactions() async {
        let apiClient = makeClientWithMatchingHealer(sourceID: 7)
        apiClient.castsResult = .success([
            CastEvent(timestamp: 1000, spellID: 33206, sourceID: 7)  // 고통 억제
        ])
        let vm = makeSUT(apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()
        vm.uncheckAllSpells()
        await vm.generate()

        if case .success(let output, _) = vm.state {
            XCTAssertEqual(output.reactionCount, 0, "전체 해제 후 reactions 비어있어야 함")
        } else {
            XCTFail("expected success")
        }
    }

    // MARK: - fightLast 에러

    func test_detectHealers_fightLast_setsFailureFightSelectionRequired() async {
        let vm = makeSUT()
        vm.reportURLText = "https://www.warcraftlogs.com/reports/AbCd1234#fight=last&source=7"
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .failure(let e) = vm.state {
            XCTAssertEqual(e, .fightSelectionRequired)
        } else {
            XCTFail("expected fightSelectionRequired")
        }
    }

    // MARK: - Keychain

    func test_detectHealers_success_savesCredentialsToKeychain() async {
        let keychain = MockKeychain()
        let apiClient = makeClientWithMatchingHealer()
        let vm = makeSUT(keychain: keychain, apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "my-client-id"
        vm.clientSecret = "my-secret"

        await vm.detectHealers()

        XCTAssertEqual(keychain.stored, "my-secret")
        XCTAssertEqual(keychain.storedClientID, "my-client-id")
    }

    func test_detectHealers_keychainSaveFails_stillProceeds() async {
        let keychain = MockKeychain()
        keychain.shouldThrowOnSave = true
        let apiClient = makeClientWithMatchingHealer()
        let vm = makeSUT(keychain: keychain, apiClient: apiClient)
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"

        await vm.detectHealers()

        if case .spellSelection = vm.state { } else {
            XCTFail("expected spellSelection even with keychain save failure")
        }
    }

    // MARK: - 기타

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

    func test_resetToIdle_clearsState() async {
        let vm = makeSUT(apiClient: makeClientWithMatchingHealer())
        vm.reportURLText = validURL
        vm.clientID = "id"
        vm.clientSecret = "secret"
        await vm.detectHealers()

        vm.resetToIdle()

        if case .idle = vm.state { } else { XCTFail("expected idle") }
        XCTAssertNil(vm.selectedHealerID)
        XCTAssertTrue(vm.selectedSpellIDs.isEmpty)
    }
}
