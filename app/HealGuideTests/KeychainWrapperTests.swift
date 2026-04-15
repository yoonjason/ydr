import XCTest
@testable import HealGuide

final class KeychainWrapperTests: XCTestCase {
    private let keychain = KeychainWrapper(service: "com.yeongseok.healguide.test", account: "client_secret")

    override func setUp() {
        super.setUp()
        keychain.delete()
        keychain.deleteClientID()
    }

    override func tearDown() {
        keychain.delete()
        keychain.deleteClientID()
        super.tearDown()
    }

    func test_saveAndLoad_returnsStored() throws {
        try keychain.save("test_secret")
        XCTAssertEqual(keychain.load(), "test_secret")
    }

    func test_saveAndDelete_returnsNil() throws {
        try keychain.save("test_secret")
        keychain.delete()
        XCTAssertNil(keychain.load())
    }

    func test_overwrite_updatesExisting() throws {
        try keychain.save("first_secret")
        try keychain.save("second_secret")
        XCTAssertEqual(keychain.load(), "second_secret")
    }

    func test_emptyStringSave_loadsEmpty() throws {
        try keychain.save("")
        XCTAssertEqual(keychain.load(), "")
    }

    func test_saveClientIDAndLoad_returnsStored() throws {
        try keychain.saveClientID("my-client-id")
        XCTAssertEqual(keychain.loadClientID(), "my-client-id")
    }

    func test_saveClientIDAndDelete_returnsNil() throws {
        try keychain.saveClientID("my-client-id")
        keychain.deleteClientID()
        XCTAssertNil(keychain.loadClientID())
    }

    func test_clientIDAndSecret_storedIndependently() throws {
        try keychain.save("my-secret")
        try keychain.saveClientID("my-client-id")

        XCTAssertEqual(keychain.load(), "my-secret")
        XCTAssertEqual(keychain.loadClientID(), "my-client-id")

        keychain.delete()
        XCTAssertNil(keychain.load())
        XCTAssertEqual(keychain.loadClientID(), "my-client-id")
    }
}
