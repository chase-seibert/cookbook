import Foundation

enum PaprikaDirectionParser {
    private static let numberedStep = try! NSRegularExpression(pattern: #"^[0-9]+[.)]\s+(.+)$"#)

    static func parse(_ directions: String) -> [String] {
        let normalized = directions
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var steps: [String] = []
        var current = ""

        func appendCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { steps.append(trimmed) }
            current = ""
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                appendCurrent()
                continue
            }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = numberedStep.firstMatch(in: line, range: range),
               let instructionRange = Range(match.range(at: 1), in: line) {
                appendCurrent()
                current = String(line[instructionRange])
            } else if current.isEmpty {
                current = line
            } else {
                current += "\n\(line)"
            }
        }
        appendCurrent()
        return steps
    }
}
