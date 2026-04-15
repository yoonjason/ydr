import XCTest
@testable import HealGuide

final class MockURLProtocol: URLProtocol {
    static var classHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.classHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: 4096)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class WarcraftLogsAPIClientImplTests: XCTestCase {
    private var client: WarcraftLogsAPIClientImpl!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = WarcraftLogsAPIClientImpl(session: session)
    }

    override func tearDown() {
        MockURLProtocol.classHandler = nil
        client = nil
        super.tearDown()
    }

    // MARK: - fetchAccessToken

    func test_fetchAccessToken_success_returnsToken() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.classHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"access_token":"test-token","token_type":"Bearer"}"#.data(using: .utf8)!
            return (response, body)
        }

        let token = try await client.fetchAccessToken(clientID: "id", clientSecret: "secret")

        XCTAssertEqual(token, "test-token")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
    }

    func test_fetchAccessToken_401_throwsAuthenticationFailed() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await client.fetchAccessToken(clientID: "id", clientSecret: "bad-secret")
            XCTFail("Expected authenticationFailed")
        } catch let error as AppError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fetchAccessToken_500_throwsNetworkError() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await client.fetchAccessToken(clientID: "id", clientSecret: "secret")
            XCTFail("Expected networkError")
        } catch let error as AppError {
            XCTAssertEqual(error, .networkError("HTTP 500"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fetchAccessToken_authorizationHeader_containsBase64Credentials() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.classHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"access_token":"token","token_type":"Bearer"}"#.data(using: .utf8)!
            return (response, body)
        }

        _ = try await client.fetchAccessToken(clientID: "myID", clientSecret: "mySecret")

        let expectedBase64 = "myID:mySecret".data(using: .utf8)!.base64EncodedString()
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Basic \(expectedBase64)")
    }

    // MARK: - fetchFight

    func test_fetchFight_success_returnsFightMeta() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.classHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "fights": [{
                      "id": 5,
                      "encounterID": 2599,
                      "name": "Ulgrax the Devourer",
                      "startTime": 1000.0,
                      "endTime": 9000.0,
                      "kill": true
                    }]
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchFight(reportCode: "AbCd1234", fightID: 5, token: "test-token")

        XCTAssertEqual(result.id, 5)
        XCTAssertEqual(result.encounterID, 2599)
        XCTAssertEqual(result.name, "Ulgrax the Devourer")
        XCTAssertEqual(result.startTime, 1000)
        XCTAssertEqual(result.endTime, 9000)
        XCTAssertTrue(result.kill)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func test_fetchFight_graphqlErrors_throwsNetworkError() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"errors": [{"message": "Fight not accessible"}], "data": null}
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.fetchFight(reportCode: "AbCd1234", fightID: 5, token: "test-token")
            XCTFail("Expected networkError")
        } catch let error as AppError {
            XCTAssertEqual(error, .networkError("Fight not accessible"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fetchFight_emptyFights_throwsFightNotFound() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data": {"reportData": {"report": {"fights": []}}}}
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.fetchFight(reportCode: "AbCd1234", fightID: 99, token: "test-token")
            XCTFail("Expected fightNotFound")
        } catch let error as AppError {
            XCTAssertEqual(error, .fightNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - fetchEncounters

    func test_fetchEncounters_success_returnsBossWindows() async throws {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [
                        {"type": "encounterstart", "timestamp": 1000, "encounterID": 2599, "name": "Ulgrax the Devourer"},
                        {"type": "encounterend",   "timestamp": 181000, "encounterID": 2599, "name": "Ulgrax the Devourer"}
                      ],
                      "nextPageTimestamp": null
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchEncounters(reportCode: "AbCd1234", fightID: 3, token: "test-token")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].encounterID, 2599)
        XCTAssertEqual(result[0].name, "Ulgrax the Devourer")
        XCTAssertEqual(result[0].startTime, 1000)
        XCTAssertEqual(result[0].endTime, 181000)
    }

    func test_fetchEncounters_emptyData_returnsEmptyArray() async throws {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [],
                      "nextPageTimestamp": null
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchEncounters(reportCode: "AbCd1234", fightID: 3, token: "test-token")

        XCTAssertTrue(result.isEmpty)
    }

    func test_fetchEncounters_multipleBosses_returnAllWindows() async throws {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [
                        {"type": "encounterstart", "timestamp": 0,      "encounterID": 2599, "name": "Boss A"},
                        {"type": "encounterend",   "timestamp": 90000,  "encounterID": 2599, "name": "Boss A"},
                        {"type": "encounterstart", "timestamp": 120000, "encounterID": 2600, "name": "Boss B"},
                        {"type": "encounterend",   "timestamp": 240000, "encounterID": 2600, "name": "Boss B"}
                      ],
                      "nextPageTimestamp": null
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchEncounters(reportCode: "AbCd1234", fightID: 3, token: "test-token")

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].encounterID, 2599)
        XCTAssertEqual(result[0].startTime, 0)
        XCTAssertEqual(result[0].endTime, 90000)
        XCTAssertEqual(result[1].encounterID, 2600)
        XCTAssertEqual(result[1].startTime, 120000)
        XCTAssertEqual(result[1].endTime, 240000)
    }

    func test_fetchEncounters_startWithoutEnd_notIncluded() async throws {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [
                        {"type": "encounterstart", "timestamp": 0, "encounterID": 2599, "name": "Boss A"}
                      ],
                      "nextPageTimestamp": null
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchEncounters(reportCode: "AbCd1234", fightID: 3, token: "test-token")

        XCTAssertTrue(result.isEmpty)
    }

    func test_fetchEncounters_pagination_startOnPage1EndOnPage2_returnsBossWindow() async throws {
        var callCount = 0
        MockURLProtocol.classHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body: Data
            if callCount == 1 {
                body = """
                {
                  "data": {
                    "reportData": {
                      "report": {
                        "events": {
                          "data": [
                            {"type": "encounterstart", "timestamp": 1000, "encounterID": 2599, "name": "Ulgrax the Devourer"}
                          ],
                          "nextPageTimestamp": 5000.0
                        }
                      }
                    }
                  }
                }
                """.data(using: .utf8)!
            } else {
                body = """
                {
                  "data": {
                    "reportData": {
                      "report": {
                        "events": {
                          "data": [
                            {"type": "encounterend", "timestamp": 181000, "encounterID": 2599, "name": "Ulgrax the Devourer"}
                          ],
                          "nextPageTimestamp": null
                        }
                      }
                    }
                  }
                }
                """.data(using: .utf8)!
            }
            return (response, body)
        }

        let result = try await client.fetchEncounters(reportCode: "AbCd1234", fightID: 3, token: "test-token")

        XCTAssertEqual(callCount, 2, "2페이지에 걸쳐 있으므로 API를 2번 호출해야 함")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].encounterID, 2599)
        XCTAssertEqual(result[0].name, "Ulgrax the Devourer")
        XCTAssertEqual(result[0].startTime, 1000)
        XCTAssertEqual(result[0].endTime, 181000)
    }

    func test_fetchEncounters_graphqlErrors_throwsNetworkError() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"errors": [{"message": "Unauthorized"}], "data": null}
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.fetchEncounters(reportCode: "AbCd1234", fightID: 3, token: "test-token")
            XCTFail("Expected networkError")
        } catch let error as AppError {
            XCTAssertEqual(error, .networkError("Unauthorized"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - fetchCasts

    func test_fetchCasts_success_returnsCastEvents() async throws {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [
                        {"type": "cast", "timestamp": 1000, "sourceID": 7, "abilityGameID": 98765},
                        {"type": "cast", "timestamp": 5000, "sourceID": 7, "abilityGameID": 11111}
                      ],
                      "nextPageTimestamp": null
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchCasts(
            reportCode: "AbCd1234", fightID: 3, sourceID: 7,
            hostilityType: .friendly, startTime: 0, endTime: 10000, token: "test-token"
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].spellID, 98765)
        XCTAssertEqual(result[0].timestamp, 1000)
        XCTAssertEqual(result[1].spellID, 11111)
    }

    func test_fetchCasts_filtersNonCastEvents() async throws {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [
                        {"type": "cast",      "timestamp": 1000, "sourceID": 7, "abilityGameID": 98765},
                        {"type": "begincast", "timestamp": 500,  "sourceID": 7, "abilityGameID": 98765}
                      ],
                      "nextPageTimestamp": null
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchCasts(
            reportCode: "AbCd1234", fightID: 3, sourceID: 7,
            hostilityType: .friendly, startTime: 0, endTime: 10000, token: "test-token"
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].spellID, 98765)
    }

    func test_fetchCasts_pagination_fetchesAllPages() async throws {
        var callCount = 0
        MockURLProtocol.classHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let nextPage: String = callCount == 1 ? "\"nextPageTimestamp\": 5000.0" : "\"nextPageTimestamp\": null"
            let spellID = callCount == 1 ? 11111 : 22222
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [{"type": "cast", "timestamp": 1000, "sourceID": 1, "abilityGameID": \(spellID)}],
                      \(nextPage)
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        let result = try await client.fetchCasts(
            reportCode: "AbCd1234", fightID: 3, sourceID: nil,
            hostilityType: .hostile, startTime: 0, endTime: 100000, token: "test-token"
        )

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].spellID, 11111)
        XCTAssertEqual(result[1].spellID, 22222)
    }

    func test_fetchCasts_paginationStopsAtEndTime() async throws {
        var callCount = 0
        MockURLProtocol.classHandler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "data": {
                "reportData": {
                  "report": {
                    "events": {
                      "data": [{"type": "cast", "timestamp": 1000, "sourceID": 1, "abilityGameID": 111}],
                      "nextPageTimestamp": 200000.0
                    }
                  }
                }
              }
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        _ = try await client.fetchCasts(
            reportCode: "AbCd1234", fightID: 3, sourceID: nil,
            hostilityType: .hostile, startTime: 0, endTime: 10000, token: "test-token"
        )

        XCTAssertEqual(callCount, 1, "nextPageTimestamp(200000) > endTime(10000)이므로 1페이지만 조회해야 함")
    }

    func test_fetchCasts_endTime_isPassedToGraphQL() async throws {
        var capturedVariables: [String: Any]?
        MockURLProtocol.classHandler = { request in
            let bodyData = MockURLProtocol.readBody(from: request)
            if let bodyData,
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let variables = json["variables"] as? [String: Any] {
                capturedVariables = variables
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"data": {"reportData": {"report": {"events": {"data": [], "nextPageTimestamp": null}}}}}
            """.data(using: .utf8)!
            return (response, body)
        }

        _ = try await client.fetchCasts(
            reportCode: "AbCd1234", fightID: 3, sourceID: nil,
            hostilityType: .hostile, startTime: 1000, endTime: 9000, token: "test-token"
        )

        let variables = try XCTUnwrap(capturedVariables)
        let endTime = try XCTUnwrap(variables["endTime"] as? Double)
        XCTAssertEqual(endTime, 9000.0)
    }

    func test_fetchCasts_graphqlErrors_throwsNetworkError() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"errors": [{"message": "Unauthorized"}], "data": null}
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.fetchCasts(
                reportCode: "AbCd1234", fightID: 3, sourceID: nil,
                hostilityType: .hostile, startTime: 0, endTime: 99999, token: "test-token"
            )
            XCTFail("Expected networkError")
        } catch let error as AppError {
            XCTAssertEqual(error, .networkError("Unauthorized"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
