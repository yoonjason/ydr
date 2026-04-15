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
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_fetchFight_graphqlErrors_throwsNetworkError() async {
        MockURLProtocol.classHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "errors": [{"message": "Fight not accessible"}],
              "data": null
            }
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
            {
              "data": {
                "reportData": {
                  "report": {
                    "fights": []
                  }
                }
              }
            }
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
}
