import XCTest
@testable import HealGuide

final class WarcraftLogsAPIClientTests: XCTestCase {
    private var mock: MockWarcraftLogsAPIClient!

    override func setUp() {
        super.setUp()
        mock = MockWarcraftLogsAPIClient()
    }

    func test_mock_fetchAccessToken_success() async throws {
        mock.tokenResult = .success("test-token-abc")
        let token = try await mock.fetchAccessToken(clientID: "id", clientSecret: "secret")
        XCTAssertEqual(token, "test-token-abc")
    }

    func test_mock_fetchAccessToken_failure_throwsAuthError() async {
        mock.tokenResult = .failure(.authenticationFailed)
        do {
            _ = try await mock.fetchAccessToken(clientID: "id", clientSecret: "bad-secret")
            XCTFail("Expected authenticationFailed to be thrown")
        } catch let error as AppError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchBossFights_anchorIsBoss() async throws {
        let expected = [BossWindow(encounterID: 2599, name: "Ulgrax", startTime: 0, endTime: 10000)]
        mock.encountersResult = .success(expected)
        let result = try await mock.fetchEncounters(reportCode: "AbCd1234", fightID: 1, token: "test-token")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].encounterID, 2599)
    }

    func testFetchBossFights_dungeonWide() async throws {
        let expected = [
            BossWindow(encounterID: 100, name: "Boss A", startTime: 1000, endTime: 5000),
            BossWindow(encounterID: 101, name: "Boss B", startTime: 6000, endTime: 10000),
            BossWindow(encounterID: 102, name: "Boss C", startTime: 11000, endTime: 15000)
        ]
        mock.encountersResult = .success(expected)
        let result = try await mock.fetchEncounters(reportCode: "AbCd1234", fightID: 1, token: "test-token")
        XCTAssertEqual(result.count, 3)
    }

    func testFetchBossFights_noBossEncounters() async {
        mock.encountersResult = .failure(.noBossEncounters)
        do {
            _ = try await mock.fetchEncounters(reportCode: "AbCd1234", fightID: 1, token: "test-token")
            XCTFail("Expected noBossEncounters to be thrown")
        } catch let error as AppError {
            XCTAssertEqual(error, .noBossEncounters)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchBossFights_fightNotFound() async {
        mock.encountersResult = .failure(.fightNotFound)
        do {
            _ = try await mock.fetchEncounters(reportCode: "AbCd1234", fightID: 99, token: "test-token")
            XCTFail("Expected fightNotFound to be thrown")
        } catch let error as AppError {
            XCTAssertEqual(error, .fightNotFound)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_mock_fetchCasts_success_returnsCasts() async throws {
        let expected = [CastEvent(timestamp: 1000, spellID: 200, sourceID: 5)]
        mock.castsResult = .success(expected)
        let result = try await mock.fetchCasts(
            reportCode: "AbCd1234", fightID: 3, sourceID: 5,
            hostilityType: .friendly, startTime: 0, endTime: 10000, token: "test-token"
        )
        XCTAssertEqual(result, expected)
    }
}
