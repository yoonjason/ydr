import XCTest
@testable import HealGuide

final class URLParserTests: XCTestCase {
    private let parser = URLParser()

    func test_validURL_returnsReportURL() throws {
        let raw = "https://www.warcraftlogs.com/reports/AbCd1234#fight=3&source=7"
        let result = try parser.parse(raw)
        XCTAssertEqual(result, ReportURL(code: "AbCd1234", fightID: 3, sourceID: 7))
    }

    func test_fightLast_throwsFightSelectionRequired() {
        let raw = "https://www.warcraftlogs.com/reports/AbCd1234#fight=last&source=7"
        XCTAssertThrowsError(try parser.parse(raw)) { error in
            XCTAssertEqual(error as? AppError, AppError.fightSelectionRequired)
        }
    }

    func test_missingSource_throwsInvalidURL() {
        let raw = "https://www.warcraftlogs.com/reports/AbCd1234#fight=3"
        XCTAssertThrowsError(try parser.parse(raw)) { error in
            XCTAssertEqual(error as? AppError, AppError.invalidURL)
        }
    }

    func test_shortCode_throwsInvalidURL() {
        // 7자 코드 — 패턴 {8,16} 불만족
        let raw = "https://www.warcraftlogs.com/reports/AbCd123#fight=3&source=7"
        XCTAssertThrowsError(try parser.parse(raw)) { error in
            XCTAssertEqual(error as? AppError, AppError.invalidURL)
        }
    }

    func test_noFragment_throwsInvalidURL() {
        let raw = "https://www.warcraftlogs.com/reports/AbCd1234"
        XCTAssertThrowsError(try parser.parse(raw)) { error in
            XCTAssertEqual(error as? AppError, AppError.invalidURL)
        }
    }

    func test_mixedCaseCode_parsed() throws {
        let raw = "https://www.warcraftlogs.com/reports/aAbBcCdDeE12#fight=1&source=2"
        let result = try parser.parse(raw)
        XCTAssertEqual(result.code, "aAbBcCdDeE12")
        XCTAssertEqual(result.fightID, 1)
        XCTAssertEqual(result.sourceID, 2)
    }

    func test_reversedQueryOrder_parsed() throws {
        let raw = "https://www.warcraftlogs.com/reports/AbCd1234#source=7&fight=3"
        let result = try parser.parse(raw)
        XCTAssertEqual(result, ReportURL(code: "AbCd1234", fightID: 3, sourceID: 7))
    }

    func test_leadingWhitespace_throwsInvalidURL() {
        let raw = " https://www.warcraftlogs.com/reports/AbCd1234#fight=3&source=7"
        XCTAssertThrowsError(try parser.parse(raw)) { error in
            XCTAssertEqual(error as? AppError, AppError.invalidURL)
        }
    }

    func test_maxLengthCode_parsed() throws {
        let raw = "https://www.warcraftlogs.com/reports/AbCd1234AbCd1234#fight=1&source=2"
        let result = try parser.parse(raw)
        XCTAssertEqual(result.code, "AbCd1234AbCd1234")
    }

    func test_wrongHost_throwsInvalidURL() {
        let raw = "https://evil.com/reports/AbCd1234#fight=3&source=7"
        XCTAssertThrowsError(try parser.parse(raw)) { error in
            XCTAssertEqual(error as? AppError, AppError.invalidURL)
        }
    }
}
