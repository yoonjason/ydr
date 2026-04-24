import Foundation
import os

protocol MemoPersistenceProtocol: Sendable {
    func filePath(wowAddonsPath: String) -> String
    func save(_ memo: MemoContent, to wowAddonsPath: String) throws -> String
    func load(from wowAddonsPath: String) -> MemoContent?
}

struct MemoPersistence: MemoPersistenceProtocol {
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "MemoPersistence")

    func filePath(wowAddonsPath: String) -> String {
        (wowAddonsPath as NSString)
            .appendingPathComponent("HealGuide/Data/HGPT_Memo.lua")
    }

    func save(_ memo: MemoContent, to wowAddonsPath: String) throws -> String {
        let path = filePath(wowAddonsPath: wowAddonsPath)
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let content = serialize(memo)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        logger.info("메모 저장: \(path)")
        return path
    }

    func load(from wowAddonsPath: String) -> MemoContent? {
        let path = filePath(wowAddonsPath: wowAddonsPath)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return deserialize(content)
    }

    // MARK: - Lua serialization (internal for tests)

    func serialize(_ memo: MemoContent) -> String {
        let unixTime = Int(Date().timeIntervalSince1970)
        let rgb = memo.fontColor.rgb
        var out: [String] = []
        out.append("-- HealGuide 상시 메모")
        out.append("-- Generated: \(unixTime)")
        out.append("-- DO NOT EDIT MANUALLY")
        out.append("")
        out.append("HGPT_Memo = {")
        out.append("    lines = {")
        for line in memo.lines {
            out.append("        '\(escapeLua(line))',")
        }
        out.append("    },")
        out.append("    fontSize = \(memo.fontSize),")
        out.append(String(
            format: "    fontColor = { r = %.1f, g = %.1f, b = %.1f, preset = '\(memo.fontColor.rawValue)' },",
            rgb.r, rgb.g, rgb.b
        ))
        out.append("    bgAlpha = \(memo.bgAlpha),")
        out.append("    updatedAt = \(unixTime),")
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }

    func deserialize(_ content: String) -> MemoContent? {
        guard let lines = parseLines(content) else {
            return parseLegacy(content)
        }
        let fontSize  = parseInt(in: content, key: "fontSize") ?? 14
        let bgAlpha   = parseInt(in: content, key: "bgAlpha") ?? 60
        let fontColor = parseFontColor(content)
        return MemoContent(lines: lines, fontSize: fontSize, fontColor: fontColor, bgAlpha: bgAlpha)
    }

    // MARK: - Private parsers

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

    // line1/line2/line3 키-값 구형 포맷 역호환
    private func parseLegacy(_ content: String) -> MemoContent? {
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
