import XCTest
@testable import HealGuide

final class MemoPersistenceTests: XCTestCase {

    private let sut = MemoPersistence()

    // MARK: - serializeBundle: 출력 포맷

    func test_serializeBundle_producesNewSchemaFormat() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["라인1", "라인2"]),
            characters: [:],
            updatedAt: 0
        )
        let output = sut.serializeBundle(bundle)

        XCTAssertTrue(output.contains("HGPT_Memo = {"))
        XCTAssertTrue(output.contains("    shared = {"))
        XCTAssertTrue(output.contains("    characters = {"))
        XCTAssertTrue(output.contains("    updatedAt = "))
        XCTAssertTrue(output.hasSuffix("\n"))
    }

    func test_serializeBundle_noCharacters_producesEmptyCharactersTable() {
        let bundle = MemoBundle(shared: MemoContent(lines: ["테스트"]), characters: [:], updatedAt: 0)
        let output = sut.serializeBundle(bundle)

        XCTAssertTrue(output.contains("    characters = {\n    },"))
    }

    func test_serializeBundle_withCharacter_producesCharacterEntry() {
        let charContent = MemoContent(lines: ["캐릭터 메모"], fontSize: 16, fontColor: .cyan, bgAlpha: 80)
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: ["캐릭터-서버": charContent],
            updatedAt: 0
        )
        let output = sut.serializeBundle(bundle)

        XCTAssertTrue(output.contains("['캐릭터-서버'] = {"))
        XCTAssertTrue(output.contains("'캐릭터 메모',"))
        XCTAssertTrue(output.contains("fontSize = 16,"))
        XCTAssertTrue(output.contains("preset = 'cyan'"))
        XCTAssertTrue(output.contains("bgAlpha = 80,"))
    }

    func test_serializeBundle_updatedAt_isNumeric() {
        let before = Int(Date().timeIntervalSince1970)
        let output = sut.serializeBundle(MemoBundle())
        let after = Int(Date().timeIntervalSince1970)

        // 최상위 updatedAt 검증
        let pattern = #"    updatedAt = (\d+),"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let numRange = Range(match.range(at: 1), in: output),
              let parsed = Int(output[numRange]) else {
            XCTFail("updatedAt이 숫자 리터럴이 아님"); return
        }
        XCTAssertGreaterThanOrEqual(parsed, before)
        XCTAssertLessThanOrEqual(parsed, after)
    }

    func test_serializeBundle_singleQuoteInLine_escaped() {
        let bundle = MemoBundle(shared: MemoContent(lines: ["it's fine"]), characters: [:], updatedAt: 0)
        let output = sut.serializeBundle(bundle)

        XCTAssertTrue(output.contains("it\\'s fine"))
    }

    // MARK: - deserializeBundle: 새 스키마 파싱

    func test_deserializeBundle_newSchema_parsesSharedAndCharacters() {
        let lua = """
        -- HealGuide 상시 메모
        HGPT_Memo = {
            shared = {
                lines = {
                    '공통줄1',
                    '공통줄2',
                },
                fontSize = 14,
                fontColor = { r = 1.0, g = 1.0, b = 1.0, preset = 'white' },
                bgAlpha = 60,
                updatedAt = 1746700000,
            },
            characters = {
                ['캐릭터-서버'] = {
                    lines = {
                        '캐릭터줄',
                    },
                    fontSize = 16,
                    fontColor = { r = 0.0, g = 1.0, b = 1.0, preset = 'cyan' },
                    bgAlpha = 80,
                    updatedAt = 1746700001,
                },
            },
            updatedAt = 1746700001,
        }
        """
        let result = sut.deserializeBundle(lua)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.shared.lines, ["공통줄1", "공통줄2"])
        XCTAssertEqual(result?.shared.fontSize, 14)
        XCTAssertEqual(result?.shared.bgAlpha, 60)

        let charContent = result?.characters["캐릭터-서버"]
        XCTAssertNotNil(charContent)
        XCTAssertEqual(charContent?.lines, ["캐릭터줄"])
        XCTAssertEqual(charContent?.fontSize, 16)
        XCTAssertEqual(charContent?.fontColor, .cyan)
        XCTAssertEqual(charContent?.bgAlpha, 80)
    }

    func test_deserializeBundle_newSchema_noCharacters_emptyDict() {
        let lua = """
        HGPT_Memo = {
            shared = {
                lines = {
                    '줄',
                },
                fontSize = 14,
                fontColor = { r = 1.0, g = 1.0, b = 1.0, preset = 'white' },
                bgAlpha = 60,
                updatedAt = 1746700000,
            },
            characters = {
            },
            updatedAt = 1746700000,
        }
        """
        let result = sut.deserializeBundle(lua)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.characters.isEmpty)
    }

    // MARK: - deserializeBundle: 레거시 스키마 → shared 흡수

    func test_deserializeBundle_legacyLinesArray_wrapsAsShared() {
        let lua = """
        HGPT_Memo = {
            lines = {
                '첫째줄',
                '둘째줄',
            },
            fontSize = 18,
            fontColor = { r = 0.0, g = 1.0, b = 1.0, preset = 'cyan' },
            bgAlpha = 75,
            updatedAt = 1745500000,
        }
        """
        let result = sut.deserializeBundle(lua)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.shared.lines, ["첫째줄", "둘째줄"])
        XCTAssertEqual(result?.shared.fontSize, 18)
        XCTAssertEqual(result?.shared.fontColor, .cyan)
        XCTAssertEqual(result?.shared.bgAlpha, 75)
        XCTAssertTrue(result!.characters.isEmpty)
    }

    func test_deserializeBundle_legacyKeyValue_wrapsAsShared() {
        let lua = """
        HGPT_Memo = {
            line1 = '첫째줄',
            line2 = '둘째줄',
            line3 = '',
            updatedAt = 1000,
        }
        """
        let result = sut.deserializeBundle(lua)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.shared.lines, ["첫째줄", "둘째줄", ""])
        XCTAssertTrue(result!.characters.isEmpty)
    }

    func test_deserializeBundle_missingOrEmpty_returnsNil() {
        XCTAssertNil(sut.deserializeBundle("-- 아무것도 없음"))
        XCTAssertNil(sut.deserializeBundle(""))
    }

    // MARK: - 왕복 (serializeBundle → deserializeBundle)

    func test_roundtrip_sharedOnly() {
        let original = MemoBundle(
            shared: MemoContent(lines: ["첫줄", "둘째"], fontSize: 18, fontColor: .cyan, bgAlpha: 80),
            characters: [:],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(original)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored, original)
    }

    func test_roundtrip_withCharacters() {
        let charContent = MemoContent(lines: ["캐릭터1"], fontSize: 16, fontColor: .yellow, bgAlpha: 70)
        let original = MemoBundle(
            shared: MemoContent(lines: ["공통"], fontSize: 14, fontColor: .white, bgAlpha: 60),
            characters: ["홍길동-로아": charContent],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(original)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored?.characters["홍길동-로아"]?.lines, ["캐릭터1"])
        XCTAssertEqual(restored?.characters["홍길동-로아"]?.fontColor, .yellow)
    }

    func test_roundtrip_multipleCharacters() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: [
                "캐릭터A-서버1": MemoContent(lines: ["A 전용"]),
                "캐릭터B-서버1": MemoContent(lines: ["B 전용"], fontColor: .red),
            ],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored, bundle)
    }

    func test_roundtrip_allColorPresets() {
        for preset in ColorPreset.allCases {
            let bundle = MemoBundle(
                shared: MemoContent(lines: ["테스트"], fontColor: preset),
                characters: [:],
                updatedAt: 0
            )
            let lua = sut.serializeBundle(bundle)
            let restored = sut.deserializeBundle(lua)
            XCTAssertEqual(restored?.shared.fontColor, preset, "\(preset.rawValue) 프리셋 왕복 실패")
        }
    }

    func test_roundtrip_specialCharactersInLines() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["it's fine", "경로\\파일", "줄\n바꿈"]),
            characters: [:],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored?.shared.lines, bundle.shared.lines)
    }

    // MARK: - balanced-brace 파서: single-quote 문자열 내 중괄호

    func test_roundtrip_closingBraceInMemoLine() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["메모에 } 포함"]),
            characters: [:],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored?.shared.lines, ["메모에 } 포함"])
        XCTAssertEqual(restored?.shared.fontSize, 14, "} 포함 시 fontSize 기본값 유지")
    }

    func test_roundtrip_escapedSingleQuoteInMemoLine() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["it's a test"]),
            characters: [:],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored?.shared.lines, ["it's a test"])
    }

    func test_roundtrip_multipleBracesInMemoLine() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["} { } test"]),
            characters: [:],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored?.shared.lines, ["} { } test"])
        XCTAssertEqual(restored?.shared.bgAlpha, 60, "} 복수 포함 시 bgAlpha 기본값 유지")
    }

    func test_roundtrip_closingBraceInCharSection_otherSectionParsedCorrectly() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: [
                "캐릭터A-서버": MemoContent(lines: ["A 메모 } 포함"]),
                "캐릭터B-서버": MemoContent(lines: ["B 정상 메모"]),
            ],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored?.characters["캐릭터A-서버"]?.lines, ["A 메모 } 포함"])
        XCTAssertEqual(restored?.characters["캐릭터B-서버"]?.lines, ["B 정상 메모"],
                       "A 캐릭터 } 때문에 B 캐릭터 파싱이 실패하면 안 됨")
    }

    func test_roundtrip_koreanCharacterKey() {
        let bundle = MemoBundle(
            shared: MemoContent(lines: ["공통"]),
            characters: ["이름-서버": MemoContent(lines: ["한글 키"])],
            updatedAt: 0
        )
        let lua = sut.serializeBundle(bundle)
        let restored = sut.deserializeBundle(lua)

        XCTAssertEqual(restored?.characters["이름-서버"]?.lines, ["한글 키"])
    }

    // MARK: - 파일 저장 / 불러오기

    func test_saveAndLoad_bundle_roundtrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoTest-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let charContent = MemoContent(lines: ["캐릭터 메모"], fontSize: 16, fontColor: .orange, bgAlpha: 70)
        let original = MemoBundle(
            shared: MemoContent(lines: ["저장테스트", "두번째"], fontSize: 14, fontColor: .white, bgAlpha: 60),
            characters: ["테스터-서버": charContent],
            updatedAt: 0
        )
        _ = try sut.save(original, to: tmpDir)

        let loaded = sut.load(from: tmpDir)
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded?.characters["테스터-서버"]?.fontColor, .orange)
    }

    func test_save_createsDirectoryIfNeeded() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoTest-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir))
        _ = try sut.save(MemoBundle(shared: MemoContent(lines: ["테스트"]), characters: [:], updatedAt: 0), to: tmpDir)

        let path = sut.filePath(wowAddonsPath: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func test_load_missingFile_returnsNil() {
        XCTAssertNil(sut.load(from: "/존재하지않는/경로"))
    }

    func test_filePath_appendsCorrectRelativePath() {
        let path = sut.filePath(wowAddonsPath: "/AddOns")
        XCTAssertEqual(path, "/AddOns/HealGuide/Data/HGPT_Memo.lua")
    }
}
