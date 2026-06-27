import Foundation

/// A value parsed from a TOML document.
enum TOMLValue: Equatable {
    case string(String)
    case bool(Bool)

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}

/// A small TOML reader covering the subset Tabbed's config needs: comments,
/// `[table]` headers, and `key = value` pairs whose values are strings or
/// booleans. Numbers, arrays, and nested tables are not supported.
enum TOML {
    /// Parse into tables keyed by header. Keys before any `[header]` live under
    /// the empty-string table.
    static func parse(_ text: String) -> [String: [String: TOMLValue]] {
        var tables: [String: [String: TOMLValue]] = ["": [:]]
        var current = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                current = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                if tables[current] == nil { tables[current] = [:] }
                continue
            }

            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = unquote(String(line[..<separator]).trimmingCharacters(in: .whitespaces))
            let raw = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !raw.isEmpty else { continue }
            tables[current, default: [:]][key] = value(from: raw)
        }

        return tables
    }

    private static func value(from raw: String) -> TOMLValue {
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        return .string(unquote(raw))
    }

    /// Drop a trailing `#` comment, ignoring `#` inside a quoted string.
    private static func stripComment(from line: String) -> String {
        var result = ""
        var quote: Character?
        for char in line {
            if let active = quote {
                if char == active { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == "#" {
                break
            }
            result.append(char)
        }
        return result
    }

    private static func unquote(_ token: String) -> String {
        guard token.count >= 2, let first = token.first, let last = token.last,
              first == last, first == "\"" || first == "'" else {
            return token
        }
        return String(token.dropFirst().dropLast())
    }
}
