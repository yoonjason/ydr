import XCTest
@testable import HealGuide

final class WoWCharacterScannerTests: XCTestCase {

    private let sut = WoWCharacterScanner()
    private var tmpRoot: URL!

    override func setUpWithError() throws {
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWScanTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpRoot!)
    }

    // MARK: - 헬퍼

    // tmpRoot 를 "_retail_" 역할로. addonsPath = tmpRoot/Interface/AddOns
    private var addonsPath: String {
        tmpRoot.appendingPathComponent("Interface/AddOns").path
    }

    private func makeCharDir(account: String, realm: String, char: String) throws -> URL {
        let url = tmpRoot
            .appendingPathComponent("WTF/Account/\(account)/\(realm)/\(char)/SavedVariables")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func placeHealGuideLua(at dir: URL) throws {
        let file = dir.appendingPathComponent("HealGuide.lua")
        try "-- stub".write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - 기본 검출

    func test_scan_singleCharacter_detected() throws {
        let dir = try makeCharDir(account: "ACCOUNT1", realm: "서버1", char: "홍길동")
        try placeHealGuideLua(at: dir)

        let results = sut.scan(wowAddonsPath: addonsPath)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "홍길동")
        XCTAssertEqual(results[0].realm, "서버1")
        XCTAssertEqual(results[0].key, "홍길동-서버1")
    }

    func test_scan_multipleCharacters_allDetected() throws {
        let dir1 = try makeCharDir(account: "ACC", realm: "서버1", char: "캐릭터A")
        let dir2 = try makeCharDir(account: "ACC", realm: "서버1", char: "캐릭터B")
        try placeHealGuideLua(at: dir1)
        try placeHealGuideLua(at: dir2)

        let results = sut.scan(wowAddonsPath: addonsPath)

        XCTAssertEqual(results.count, 2)
        let keys = Set(results.map(\.key))
        XCTAssertTrue(keys.contains("캐릭터A-서버1"))
        XCTAssertTrue(keys.contains("캐릭터B-서버1"))
    }

    func test_scan_noHealGuideLua_notDetected() throws {
        // HealGuide.lua 없이 디렉토리만 생성
        let svDir = tmpRoot
            .appendingPathComponent("WTF/Account/ACC/서버1/캐릭터X/SavedVariables")
        try FileManager.default.createDirectory(at: svDir, withIntermediateDirectories: true)

        let results = sut.scan(wowAddonsPath: addonsPath)

        XCTAssertTrue(results.isEmpty)
    }

    func test_scan_multipleAccounts_deduplicatesByKey() throws {
        let dir1 = try makeCharDir(account: "ACC1", realm: "서버1", char: "홍길동")
        let dir2 = try makeCharDir(account: "ACC2", realm: "서버1", char: "홍길동")
        try placeHealGuideLua(at: dir1)
        try placeHealGuideLua(at: dir2)

        let results = sut.scan(wowAddonsPath: addonsPath)

        XCTAssertEqual(results.count, 1, "같은 키는 중복 제거")
        XCTAssertEqual(results[0].key, "홍길동-서버1")
    }

    func test_scan_realmWithSpaces_keyStripsSpaces() throws {
        let dir = try makeCharDir(account: "ACC", realm: "Burning Blade", char: "MyChar")
        try placeHealGuideLua(at: dir)

        let results = sut.scan(wowAddonsPath: addonsPath)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].realm, "Burning Blade")
        XCTAssertEqual(results[0].key, "MyChar-BurningBlade")
    }

    func test_scan_emptyAddonsPath_returnsEmpty() {
        XCTAssertTrue(sut.scan(wowAddonsPath: "").isEmpty)
    }

    func test_scan_noWTFDirectory_returnsEmpty() {
        let results = sut.scan(wowAddonsPath: addonsPath)
        XCTAssertTrue(results.isEmpty)
    }

    func test_scan_resultsAreSortedByKey() throws {
        let dirB = try makeCharDir(account: "ACC", realm: "서버1", char: "캐릭터B")
        let dirA = try makeCharDir(account: "ACC", realm: "서버1", char: "캐릭터A")
        try placeHealGuideLua(at: dirA)
        try placeHealGuideLua(at: dirB)

        let results = sut.scan(wowAddonsPath: addonsPath)

        XCTAssertEqual(results.map(\.name), ["캐릭터A", "캐릭터B"])
    }

    // MARK: - scanWithDiagnostic

    func test_scanWithDiagnostic_success_returnsCharactersAndNilMessage() throws {
        let dir = try makeCharDir(account: "ACC", realm: "서버1", char: "홍길동")
        try placeHealGuideLua(at: dir)

        let result = sut.scanWithDiagnostic(wowAddonsPath: addonsPath)

        XCTAssertEqual(result.characters.count, 1)
        XCTAssertNil(result.message, "캐릭터 탐지 성공 시 message nil")
    }

    func test_scanWithDiagnostic_noWTF_returnsEmptyAndMessage() {
        let result = sut.scanWithDiagnostic(wowAddonsPath: addonsPath)

        XCTAssertTrue(result.characters.isEmpty)
        XCTAssertNotNil(result.message, "WTF 없으면 안내 메시지 있어야 함")
    }

    func test_scanWithDiagnostic_noCharacters_returnsEmptyAndMessage() throws {
        let wtfDir = tmpRoot.appendingPathComponent("WTF/Account")
        try FileManager.default.createDirectory(at: wtfDir, withIntermediateDirectories: true)

        let result = sut.scanWithDiagnostic(wowAddonsPath: addonsPath)

        XCTAssertTrue(result.characters.isEmpty)
        XCTAssertNotNil(result.message, "캐릭터 없으면 안내 메시지 있어야 함")
    }

    func test_scanWithDiagnostic_emptyPath_returnsEmptyAndMessage() {
        let result = sut.scanWithDiagnostic(wowAddonsPath: "")

        XCTAssertTrue(result.characters.isEmpty)
        XCTAssertNotNil(result.message)
    }

    // MARK: - WoWCharacter.key

    func test_characterKey_stripsSpacesFromRealm() {
        let char = WoWCharacter(realm: "My Realm", name: "Hero")
        XCTAssertEqual(char.key, "Hero-MyRealm")
    }

    func test_characterKey_koreanRealm_preserved() {
        let char = WoWCharacter(realm: "한국서버", name: "캐릭터")
        XCTAssertEqual(char.key, "캐릭터-한국서버")
    }
}
