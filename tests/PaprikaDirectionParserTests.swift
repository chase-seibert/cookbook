import Foundation

@main
struct PaprikaDirectionParserTests {
    static func main() throws {
        let screenshotDirections = (1...7).map { "\($0). Direction \($0)" }.joined(separator: "\n")
        try require(
            PaprikaDirectionParser.parse(screenshotDirections) == (1...7).map { "Direction \($0)" },
            "seven numbered lines should become seven clean steps in order"
        )
        try require(
            PaprikaDirectionParser.parse("1. Rinse rice\n2) Heat oil\n3. Add onion") == ["Rinse rice", "Heat oil", "Add onion"],
            "period and parenthesis numbering should split and strip only the marker"
        )
        try require(
            PaprikaDirectionParser.parse("1. Mix the ingredients\nuntil smooth.\n2. Bake until set.") == ["Mix the ingredients\nuntil smooth.", "Bake until set."],
            "unnumbered wrapped lines should remain with the current numbered step"
        )
        try require(
            PaprikaDirectionParser.parse("First mix everything\nuntil smooth.") == ["First mix everything\nuntil smooth."],
            "unnumbered wrapped prose should remain one step"
        )
        try require(
            PaprikaDirectionParser.parse("First step.\n\nSecond step.\n\n\nThird step.") == ["First step.", "Second step.", "Third step."],
            "blank paragraphs should continue to separate steps and ignore empty lines"
        )
        try require(
            PaprikaDirectionParser.parse("1. First step.\r\n2. Second step.\r\n") == ["First step.", "Second step."],
            "CRLF line endings should parse like LF"
        )
        try require(
            PaprikaDirectionParser.parse("Stir for 1.5 minutes, then check.") == ["Stir for 1.5 minutes, then check."],
            "numbering inside prose should not create step boundaries"
        )
        print("Paprika direction parser checks passed")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message: message) }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
