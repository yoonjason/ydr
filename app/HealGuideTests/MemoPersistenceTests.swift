import XCTest
@testable import HealGuide

final class MemoPersistenceTests: XCTestCase {

    private let sut = MemoPersistence()

    // MARK: - serialize: 출력 포맷

    func test_serialize_producesHGPT_MemoStructure() {
        let memo = MemoContent(lines: ["라인1", "라인2", "라인3"])
        let output = sut.serialize(memo)

        XCTAssertTrue(output.contains("HGPT_Memo = {"))
        XCTAssertTrue(output.contains("lines = {"))
        XCTAssertTrue(output.contains("updatedAt = "))
        XCTAssertFalse(output.contains("updatedAt = '"), "updatedAt은 따옴표 없는 숫자여야 함")
        XCTAssertTrue(output.hasSuffix("\n"))
    }

    func test_serialize_allLinesPresent() {
        let memo = MemoContent(lines: ["첫줄", "둘째줄", "셋째줄"])
        let output = sut.serialize(memo)

        XCTAssertTrue(output.contains("'첫줄',"))
        XCTAssertTrue(output.contains("'둘째줄',"))
        XCTAssertTrue(output.contains("'셋째줄',"))
    }

    func test_serialize_emptyLinesArray_producesNoLineEntries() {
        let output = sut.serialize(MemoContent(lines: []))

        XCTAssertTrue(output.contains("lines = {"), "lines 블록은 항상 출력")
        XCTAssertFalse(output.contains("'',"), "빈 라인 배열은 항목 없음")
    }

    func test_serialize_includesNewFields() {
        let memo = MemoContent(lines: ["테스트"], fontSize: 20, fontColor: .cyan, bgAlpha: 80)
        let output = sut.serialize(memo)

        XCTAssertTrue(output.contains("fontSize = 20,"))
        XCTAssertTrue(output.contains("preset = 'cyan'"))
        XCTAssertTrue(output.contains("bgAlpha = 80,"))
    }

    func test_serialize_fontColor_includesRGBAndPreset() {
        let memo = MemoContent(lines: [], fontColor: .yellow)
        let output = sut.serialize(memo)

        XCTAssertTrue(output.contains("r = 1.0"), "r 값 포함")
        XCTAssertTrue(output.contains("g = 0.9"), "g 값 포함")
        XCTAssertTrue(output.contains("b = 0.2"), "b 값 포함")
        XCTAssertTrue(output.contains("preset = 'yellow'"))
    }

    // MARK: - serialize: 이스케이프

    func test_serialize_singleQuoteEscaped() {
        let memo = MemoContent(lines: ["it's fine"])
        let output = sut.serialize(memo)

        XCTAssertFalse(output.contains("'it's fine'"), "이스케이프 안 된 단일 인용부호 없어야 함")
        XCTAssertTrue(output.contains("it\\'s fine"), "단일 인용부호가 \\' 로 이스케이프 되어야 함")
    }

    func test_serialize_newlineEscaped() {
        let memo = MemoContent(lines: ["줄\n바꿈"])
        let output = sut.serialize(memo)

        XCTAssertFalse(output.contains("줄\n바꿈"), "이스케이프 안 된 개행 없어야 함")
        XCTAssertTrue(output.contains("줄\\n바꿈"), "개행이 \\n으로 이스케이프되어야 함")
    }

    func test_serialize_backslashEscaped() {
        let memo = MemoContent(lines: ["경로\\파일"])
        let output = sut.serialize(memo)

        XCTAssertTrue(output.contains("경로\\\\파일"), "역슬래시가 \\\\ 로 이스케이프되어야 함")
    }

    func test_serialize_tabEscaped() {
        let memo = MemoContent(lines: ["탭\t문자"])
        let output = sut.serialize(memo)

        XCTAssertFalse(output.contains("탭\t문자"))
        XCTAssertTrue(output.contains("탭\\t문자"))
    }

    func test_serialize_updatedAt_isNumeric() {
        let before = Int(Date().timeIntervalSince1970)
        let output = sut.serialize(MemoContent())
        let after = Int(Date().timeIntervalSince1970)

        let numericPattern = #"updatedAt = (\d+),"#
        let regex = try! NSRegularExpression(pattern: numericPattern)
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let numRange = Range(match.range(at: 1), in: output),
              let parsed = Int(output[numRange]) else {
            XCTFail("updatedAt이 숫자 리터럴이 아님")
            return
        }
        XCTAssertGreaterThanOrEqual(parsed, before)
        XCTAssertLessThanOrEqual(parsed, after)
        XCTAssertFalse(output.contains("updatedAt = '"), "updatedAt은 따옴표 없는 숫자여야 함")
    }

    // MARK: - deserialize: 파싱

    func test_deserialize_validLua_returnsCorrectLines() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '첫째줄',
                '둘째줄',
                '셋째줄',
            },
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lines.count, 3)
        XCTAssertEqual(result?.lines[0], "첫째줄")
        XCTAssertEqual(result?.lines[1], "둘째줄")
        XCTAssertEqual(result?.lines[2], "셋째줄")
    }

    func test_deserialize_parsesNewFields() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '테스트',
            },
            fontSize = 18,
            fontColor = { r = 0.3, g = 0.9, b = 1.0, preset = 'cyan' },
            bgAlpha = 75,
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertEqual(result?.fontSize, 18)
        XCTAssertEqual(result?.fontColor, .cyan)
        XCTAssertEqual(result?.bgAlpha, 75)
    }

    func test_deserialize_missingNewFields_usesDefaults() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '줄',
            },
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertEqual(result?.fontSize, 14)
        XCTAssertEqual(result?.fontColor, .white)
        XCTAssertEqual(result?.bgAlpha, 60)
    }

    func test_deserialize_emptyLines_returnsEmptyArray() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '',
                '',
                '',
            },
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lines, ["", "", ""])
    }

    func test_deserialize_escapedSingleQuote_unescaped() {
        let lua = """
        HGPT_Memo = {
            lines = {
                'it\\'s fine',
                '',
            },
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertEqual(result?.lines[0], "it's fine")
    }

    func test_deserialize_escapedNewline_unescaped() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '줄\\n바꿈',
                '',
            },
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertEqual(result?.lines[0], "줄\n바꿈")
    }

    func test_deserialize_curlyBracesInLines() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '{기믹} 주의',
                '{today\\'s plan}',
                '',
            },
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertEqual(result?.lines[0], "{기믹} 주의")
        XCTAssertEqual(result?.lines[1], "{today's plan}")
        XCTAssertEqual(result?.lines[2], "")
    }

    func test_deserialize_missingLuaBlock_returnsNil() {
        XCTAssertNil(sut.deserialize("-- 아무것도 없음"))
        XCTAssertNil(sut.deserialize(""))
    }

    // MARK: - deserialize: 역호환 (line1/line2/line3 키-값 포맷)

    func test_deserialize_legacyKeyValue_returnsLines() {
        let lua = """
        HGPT_Memo = {
            line1 = '첫째줄',
            line2 = '둘째줄',
            line3 = '',
            updatedAt = 1000,
        }
        """
        let result = sut.deserialize(lua)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lines, ["첫째줄", "둘째줄", ""])
        XCTAssertEqual(result?.fontSize, 14, "기본값 유지")
        XCTAssertEqual(result?.fontColor, .white, "기본값 유지")
        XCTAssertEqual(result?.bgAlpha, 60, "기본값 유지")
    }

    func test_deserialize_legacyAllEmpty_returnsNil() {
        let lua = """
        HGPT_Memo = {
            line1 = '',
            line2 = '',
            line3 = '',
        }
        """
        XCTAssertNil(sut.deserialize(lua), "모두 빈 레거시 포맷은 nil")
    }

    // MARK: - 왕복 (serialize → deserialize)

    func test_roundtrip_plainText() {
        let original = MemoContent(lines: ["첫줄 메모", "두번째", "세번째"])
        let lua = sut.serialize(original)
        let restored = sut.deserialize(lua)

        XCTAssertEqual(restored, original)
    }

    func test_roundtrip_withNewFields() {
        let original = MemoContent(
            lines: ["힐사이클", "1. 쿨마다 사용"],
            fontSize: 18,
            fontColor: .cyan,
            bgAlpha: 80
        )
        let lua = sut.serialize(original)
        let restored = sut.deserialize(lua)

        XCTAssertEqual(restored, original)
    }

    func test_roundtrip_allColorPresets() {
        for preset in ColorPreset.allCases {
            let original = MemoContent(lines: ["테스트"], fontColor: preset)
            let lua = sut.serialize(original)
            let restored = sut.deserialize(lua)
            XCTAssertEqual(restored?.fontColor, preset, "\(preset.rawValue) 프리셋 왕복 실패")
        }
    }

    func test_roundtrip_specialCharacters() {
        let original = MemoContent(lines: [
            "it's \"great\" \\path",
            "줄\n바꿈\t탭",
            "백슬래시\\\\ 끝",
        ])
        let lua = sut.serialize(original)
        let restored = sut.deserialize(lua)

        XCTAssertEqual(restored?.lines, original.lines)
    }

    func test_roundtrip_curlyBracesInContent() {
        let original = MemoContent(lines: ["{기믹} 주의", "{today's plan}", "끝}"])
        let lua = sut.serialize(original)
        let restored = sut.deserialize(lua)

        XCTAssertEqual(restored, original)
    }

    func test_roundtrip_manyLines() {
        let lines = (1...10).map { "줄 \($0)" }
        let original = MemoContent(lines: lines)
        let lua = sut.serialize(original)
        let restored = sut.deserialize(lua)

        XCTAssertEqual(restored?.lines, lines)
    }

    func test_roundtrip_emptyMemo() {
        let original = MemoContent()
        let lua = sut.serialize(original)
        let restored = sut.deserialize(lua)

        XCTAssertEqual(restored, original)
    }

    // MARK: - 파일 저장 / 불러오기

    func test_saveAndLoad_roundtrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoTest-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let original = MemoContent(
            lines: ["저장테스트", "두번째", "세번째"],
            fontSize: 16,
            fontColor: .orange,
            bgAlpha: 70
        )
        _ = try sut.save(original, to: tmpDir)

        let loaded = sut.load(from: tmpDir)
        XCTAssertEqual(loaded, original)
    }

    func test_save_createsDirectoryIfNeeded() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoTest-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir))
        _ = try sut.save(MemoContent(lines: ["테스트"]), to: tmpDir)

        let path = sut.filePath(wowAddonsPath: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func test_load_missingFile_returnsNil() {
        let result = sut.load(from: "/존재하지않는/경로")
        XCTAssertNil(result)
    }

    func test_filePath_appendsCorrectRelativePath() {
        let path = sut.filePath(wowAddonsPath: "/AddOns")
        XCTAssertEqual(path, "/AddOns/HealGuide/Data/HGPT_Memo.lua")
    }
}
