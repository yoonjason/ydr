import XCTest
@testable import HealGuide

final class KeychainWrapperTests: XCTestCase {
    private let keychain = KeychainWrapper(service: "com.yeongseok.healguide.test", account: "client_secret")

    override func setUp() {
        super.setUp()
        keychain.delete()
    }

    override func tearDown() {
        keychain.delete()
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
}
