import Foundation
import os

protocol MemoPersistenceProtocol: Sendable {
    func filePath(wowAddonsPath: String) -> String
    func save(_ bundle: MemoBundle, to wowAddonsPath: String) throws -> String
    func load(from wowAddonsPath: String) -> MemoBundle?
}

struct MemoPersistence: MemoPersistenceProtocol {
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "MemoPersistence")

    func filePath(wowAddonsPath: String) -> String {
        (wowAddonsPath as NSString)
            .appendingPathComponent("HealGuide/Data/HGPT_Memo.lua")
    }

    func save(_ bundle: MemoBundle, to wowAddonsPath: String) throws -> String {
        let path = filePath(wowAddonsPath: wowAddonsPath)
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let content = serializeBundle(bundle)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        logger.info("메모 저장: \(path)")
        return path
    }

    func load(from wowAddonsPath: String) -> MemoBundle? {
        let path = filePath(wowAddonsPath: wowAddonsPath)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return deserializeBundle(content)
    }

    // MARK: - Bundle serialization (internal for tests)

    func serializeBundle(_ bundle: MemoBundle) -> String {
        let now = bundle.updatedAt > 0 ? bundle.updatedAt : Int(Date().timeIntervalSince1970)
        var out: [String] = []
        out.append("-- HealGuide 상시 메모")
        out.append("-- Generated: \(now)")
        out.append("-- DO NOT EDIT MANUALLY")
        out.append("")
        out.append("HGPT_Memo = {")
        out.append("    shared = {")
        out.append(contentsOf: serializeSectionLines(bundle.shared, indent: "        "))
        out.append("    },")
        out.append("    characters = {")
        for key in bundle.characters.keys.sorted() {
            guard let section = bundle.characters[key] else { continue }
            out.append("        ['\(escapeLua(key))'] = {")
            out.append(contentsOf: serializeSectionLines(section, indent: "            "))
            out.append("        },")
        }
        out.append("    },")
        out.append("    updatedAt = \(now),")
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }

    func deserializeBundle(_ content: String) -> MemoBundle? {
        let isNewSchema = content.contains("    shared = {") || content.contains("    characters = {")

        if isNewSchema {
            return parseNewSchema(content)
        } else {
            // 레거시 단일 스키마 → shared 로 흡수
            guard let legacy = parseLegacySingleContent(content) else { return nil }
            let bundleAt = legacy.updatedAt
            return MemoBundle(shared: legacy, characters: [:], updatedAt: bundleAt)
        }
    }

    // MARK: - Private: new-schema parser

    private func parseNewSchema(_ content: String) -> MemoBundle? {
        let sharedBlock = extractBalancedBlock(from: content, keyword: "shared")
        let shared: MemoContent
        if let block = sharedBlock {
            shared = parseSectionBlock(block)
        } else {
            shared = MemoContent()
        }

        var characters: [String: MemoContent] = [:]
        if let charsBlock = extractBalancedBlock(from: content, keyword: "characters") {
            for (key, block) in extractCharacterEntries(from: charsBlock) {
                characters[key] = parseSectionBlock(block)
            }
        }

        let bundleAt = parseInt(in: content, key: "updatedAt") ?? 0
        return MemoBundle(shared: shared, characters: characters, updatedAt: bundleAt)
    }

    // MARK: - Private: balanced-block extractor

    private func extractBalancedBlock(from content: String, keyword: String) -> String? {
        var cursor = content.startIndex
        while cursor < content.endIndex {
            guard let kwRange = content.range(of: keyword, range: cursor..<content.endIndex) else { return nil }

            // keyword 직후를 스캔: whitespace → '=' → whitespace → '{'
            var after = kwRange.upperBound
            while after < content.endIndex && content[after].isWhitespace { after = content.index(after: after) }
            guard after < content.endIndex && content[after] == "=" else {
                cursor = kwRange.upperBound; continue
            }
            after = content.index(after: after)
            while after < content.endIndex && content[after].isWhitespace { after = content.index(after: after) }
            guard after < content.endIndex && content[after] == "{" else {
                cursor = kwRange.upperBound; continue
            }

            // brace-counting (single-quote 문자열 내 중괄호 무시)
            guard let end = Self.scanBalancedBlock(in: content, from: after) else { return nil }
            return String(content[after...end])
        }
        return nil
    }

    private func extractCharacterEntries(from block: String) -> [(key: String, block: String)] {
        var results: [(key: String, block: String)] = []
        let pattern = #"\['([^']*)'\]\s*="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: block, range: NSRange(block.startIndex..., in: block))
        for match in matches {
            guard match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: block),
                  let matchRange = Range(match.range(at: 0), in: block) else { continue }

            let charKey = String(block[keyRange])

            // find '{' after '='
            var after = matchRange.upperBound
            while after < block.endIndex && (block[after].isWhitespace || block[after] == "=") {
                after = block.index(after: after)
            }
            guard after < block.endIndex && block[after] == "{" else { continue }

            guard let end = Self.scanBalancedBlock(in: block, from: after) else { continue }
            results.append((key: charKey, block: String(block[after...end])))
        }
        return results
    }

    // MARK: - Private: balanced-block scanner

    // '{' 에서 시작하여 대응하는 '}' 의 인덱스를 반환. single-quote 문자열 내 중괄호는 무시.
    private static func scanBalancedBlock(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escape = false
        while index < text.endIndex {
            let ch = text[index]
            if escape {
                escape = false
            } else if ch == "\\" && inString {
                escape = true
            } else if ch == "'" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Private: section-level parsers

    private func parseSectionBlock(_ block: String) -> MemoContent {
        let lines = parseLines(block) ?? []
        let fontSize = parseInt(in: block, key: "fontSize") ?? 14
        let bgAlpha = parseInt(in: block, key: "bgAlpha") ?? 60
        let fontColor = parseFontColor(block)
        let updatedAt = parseInt(in: block, key: "updatedAt") ?? 0
        return MemoContent(lines: lines, fontSize: fontSize, fontColor: fontColor, bgAlpha: bgAlpha, updatedAt: updatedAt)
    }

    private func parseLegacySingleContent(_ content: String) -> MemoContent? {
        // 신 lines 배열 포맷
        if let lines = parseLines(content) {
            let fontSize = parseInt(in: content, key: "fontSize") ?? 14
            let bgAlpha = parseInt(in: content, key: "bgAlpha") ?? 60
            let fontColor = parseFontColor(content)
            let updatedAt = parseInt(in: content, key: "updatedAt") ?? 0
            return MemoContent(lines: lines, fontSize: fontSize, fontColor: fontColor, bgAlpha: bgAlpha, updatedAt: updatedAt)
        }
        // 구형 line1/line2/line3 키-값 포맷
        return parseLegacyKeyValue(content)
    }

    private func parseLegacyKeyValue(_ content: String) -> MemoContent? {
        var lines: [String] = []
        var hasAnyValue = false
        for key in ["line1", "line2", "line3"] {
            let pattern = "\(key)\\s*=\\s*'((?:[^'\\\\]|\\\\.)*)'"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: content) {
                let value = unescapeLua(String(content[range]))
                lines.append(value)
                if !value.isEmpty { hasAnyValue = true }
            } else {
                lines.append("")
            }
        }
        guard hasAnyValue else { return nil }
        return MemoContent(lines: lines)
    }

    // MARK: - Private: section serializer helper

    private func serializeSectionLines(_ memo: MemoContent, indent: String) -> [String] {
        let ts = memo.updatedAt > 0 ? memo.updatedAt : Int(Date().timeIntervalSince1970)
        let rgb = memo.fontColor.rgb
        var out: [String] = []
        out.append("\(indent)lines = {")
        for line in memo.lines {
            out.append("\(indent)    '\(escapeLua(line))',")
        }
        out.append("\(indent)},")
        out.append("\(indent)fontSize = \(memo.fontSize),")
        out.append(String(
            format: "\(indent)fontColor = { r = %.1f, g = %.1f, b = %.1f, preset = '\(memo.fontColor.rawValue)' },",
            rgb.r, rgb.g, rgb.b
        ))
        out.append("\(indent)bgAlpha = \(memo.bgAlpha),")
        out.append("\(indent)updatedAt = \(ts),")
        return out
    }

    // MARK: - Shared parse helpers

    private func parseLines(_ content: String) -> [String]? {
        let blockPattern = #"lines\s*=\s*\{([\s\S]*?)\n\s*\},"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern),
              let blockMatch = blockRegex.firstMatch(
                  in: content,
                  range: NSRange(content.startIndex..., in: content)
              ),
              blockMatch.numberOfRanges > 1,
              let blockRange = Range(blockMatch.range(at: 1), in: content) else { return nil }
        let block = String(content[blockRange])

        let pattern = #"'((?:[^'\\]|\\.)*)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsBlock = block as NSString
        let matches = regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return unescapeLua(nsBlock.substring(with: range))
        }
    }

    private func parseInt(in content: String, key: String) -> Int? {
        let pattern = "\(key)\\s*=\\s*(\\d+),"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return Int(content[range])
    }

    private func parseFontColor(_ content: String) -> ColorPreset {
        let blockPattern = #"fontColor\s*=\s*\{([^}]*)\}"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern),
              let blockMatch = blockRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              blockMatch.numberOfRanges > 1,
              let blockRange = Range(blockMatch.range(at: 1), in: content) else { return .white }
        let block = String(content[blockRange])

        let presetPattern = #"preset\s*=\s*'([a-z]+)'"#
        if let regex = try? NSRegularExpression(pattern: presetPattern),
           let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: block),
           let preset = ColorPreset(rawValue: String(block[range])) {
            return preset
        }

        let r = parseDouble(in: block, key: "r") ?? 1.0
        let g = parseDouble(in: block, key: "g") ?? 1.0
        let b = parseDouble(in: block, key: "b") ?? 1.0
        return ColorPreset.nearest(r: r, g: g, b: b)
    }

    private func parseDouble(in text: String, key: String) -> Double? {
        let pattern = "\\b\(key)\\s*=\\s*([0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    // MARK: - Escape helpers

    private func escapeLua(_ str: String) -> String {
        var result = ""
        for c in str {
            switch c {
            case "\\": result += "\\\\"
            case "'":  result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:   result.append(c)
            }
        }
        return result
    }

    private func unescapeLua(_ str: String) -> String {
        var result = ""
        var i = str.startIndex
        while i < str.endIndex {
            let c = str[i]
            if c == "\\" {
                let next = str.index(after: i)
                if next < str.endIndex {
                    switch str[next] {
                    case "'":  result.append("'")
                    case "\\": result.append("\\")
                    case "n":  result.append("\n")
                    case "r":  result.append("\r")
                    case "t":  result.append("\t")
                    default:
                        result.append(c)
                        result.append(str[next])
                    }
                    i = str.index(after: next)
                } else {
                    result.append(c)
                    i = str.index(after: i)
                }
            } else {
                result.append(c)
                i = str.index(after: i)
            }
        }
        return result
    }
}
