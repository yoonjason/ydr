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

    func test_mock_fetchFight_success_returnsFightMeta() async throws {
        let expected = FightMeta(id: 5, encounterID: 2599, name: "Ulgrax the Devourer", startTime: 1000, endTime: 9000, kill: true)
        mock.fightResult = .success(expected)
        let result = try await mock.fetchFight(reportCode: "AbCd1234", fightID: 5, token: "test-token")
        XCTAssertEqual(result, expected)
    }

    func test_mock_fetchFight_failure_throwsFightNotFound() async {
        mock.fightResult = .failure(.fightNotFound)
        do {
            _ = try await mock.fetchFight(reportCode: "AbCd1234", fightID: 99, token: "test-token")
            XCTFail("Expected fightNotFound to be thrown")
        } catch let error as AppError {
            XCTAssertEqual(error, .fightNotFound)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
