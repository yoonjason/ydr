import Foundation

enum LuaSerializer {
    static func serialize(_ value: Any, indent: String = "") -> String {
        switch value {
        case let string as String:
            return "\"\(escapeLua(string))\""
        case let number as Int:
            return "\(number)"
        case let number as Int64:
            return "\(number)"
        case let number as Double:
            return String(format: "%g", number)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let dict as [String: Any]:
            return serializeStringKeyedTable(dict, indent: indent)
        case let dict as [Int: Any]:
            return serializeIntKeyedTable(dict, indent: indent)
        case let array as [Any]:
            return serializeArray(array, indent: indent)
        default:
            return "nil"
        }
    }

    private static func serializeStringKeyedTable(_ dict: [String: Any], indent: String) -> String {
        if dict.isEmpty { return "{}" }
        let inner = indent + "  "
        var lines: [String] = ["{"]
        for key in dict.keys.sorted() {
            let valueStr = serialize(dict[key]!, indent: inner)
            if isValidIdentifier(key) {
                lines.append("\(inner)\(key) = \(valueStr),")
            } else {
                lines.append("\(inner)[\"\(escapeLua(key))\"] = \(valueStr),")
            }
        }
        lines.append("\(indent)}")
        return lines.joined(separator: "\n")
    }

    private static func serializeIntKeyedTable(_ dict: [Int: Any], indent: String) -> String {
        if dict.isEmpty { return "{}" }
        let inner = indent + "  "
        var lines: [String] = ["{"]
        for key in dict.keys.sorted() {
            let valueStr = serialize(dict[key]!, indent: inner)
            lines.append("\(inner)[\(key)] = \(valueStr),")
        }
        lines.append("\(indent)}")
        return lines.joined(separator: "\n")
    }

    private static func serializeArray(_ array: [Any], indent: String) -> String {
        if array.isEmpty { return "{}" }
        let inner = indent + "  "
        var lines: [String] = ["{"]
        for item in array {
            lines.append("\(inner)\(serialize(item, indent: inner)),")
        }
        lines.append("\(indent)}")
        return lines.joined(separator: "\n")
    }

    private static func escapeLua(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
           .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func isValidIdentifier(_ str: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_]*$"#
        return str.range(of: pattern, options: .regularExpression) != nil
    }
}
