import Foundation

/// Lossless INI round-trip for `scores.ini`: every original line is preserved
/// verbatim, so comments, ordering and unparsable lines survive a save.
/// Only the single line backing an edited key is rewritten.
struct ScoresConfig {
    private(set) var lines: [String]        // original file, line by line
    private(set) var index: [String: Int]   // lowercased key -> line number
    private(set) var scores: [String: Int]  // parsed values incl. "default"

    var defaultScore: Int { scores["default"] ?? 5 }

    private static let sectionName = "scores"

    static func parse(_ text: String) -> ScoresConfig {
        let lines = text.components(separatedBy: "\n")
        var index: [String: Int] = [:]
        var scores: [String: Int] = [:]
        var inScores = false

        for (number, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inScores = Self.headerName(trimmed) == Self.sectionName
                continue
            }
            guard inScores else { continue }
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("[") {
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }

            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            let rawValue = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard let value = Int(rawValue) else { continue }

            index[key] = number
            scores[key] = Self.clamp(value)
        }

        return ScoresConfig(lines: lines, index: index, scores: scores)
    }

    /// Sets `key` to `value` (clamped to `0...10`), rewriting at most one line.
    mutating func set(_ key: String, _ value: Int) {
        let v = Self.clamp(value)
        let k = key.lowercased()

        if let number = index[k], number < lines.count,
           let eq = lines[number].firstIndex(of: "=") {
            // Preserve the original key spelling and the spacing before `=`.
            lines[number] = String(lines[number][..<eq]) + "= \(v)"
        } else {
            if !hasScoresSection {
                lines.insert("[\(Self.sectionName)]", at: 0)
                index = index.mapValues { $0 + 1 }
            }
            lines.append("\(k) = \(v)")
            index[k] = lines.count - 1
        }
        scores[k] = v
    }

    func serialized() -> String {
        let joined = lines.joined(separator: "\n")
        return joined.hasSuffix("\n") ? joined : joined + "\n"
    }

    private var hasScoresSection: Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return false }
            return Self.headerName(trimmed) == Self.sectionName
        }
    }

    /// `"[ Scores ]"` -> `"scores"`. Expects an already-trimmed `[...]` line.
    private static func headerName(_ trimmedLine: String) -> String {
        trimmedLine.dropFirst().dropLast()
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private static func clamp(_ value: Int) -> Int { min(10, max(0, value)) }
}
