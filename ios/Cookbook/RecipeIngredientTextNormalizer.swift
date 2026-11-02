import Foundation

struct NormalizedRecipeIngredientText: Equatable {
    let amount: String
    let unit: String
    let description: String
}

struct NormalizedRecipeColumns: Equatable {
    let quantity: String
    let ingredient: String
}

enum RecipeIngredientTextNormalizer {
    private static let amountOnly = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:\d+\s+)?(?:\d+(?:[./]\d+)?|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚])(?:\s*(?:-|–|—|to)\s*(?:\d+(?:[./]\d+)?|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]))?)\s*$"#,
        options: [.caseInsensitive]
    )
    private static let amountWithUnit = try! NSRegularExpression(
        pattern: #"^\s*((?:\d+\s+)?(?:\d+\s*/\s*\d+|\d+(?:[.,]\d+)?|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚])(?:\s*(?:-|–|—|to)\s*(?:\d+\s*/\s*\d+|\d+(?:[.,]\d+)?|\d+\s*[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]))?)\s+(.+?)\s*$"#,
        options: [.caseInsensitive]
    )
    private static let unit = try! NSRegularExpression(
        pattern: #"^\s*(fluid\s+ounces?|tablespoons?|teaspoons?|ounces?|pounds?|lbs?\.?|cups?|quarts?|pints?|gallons?|grams?|kilograms?|milligrams?|milliliters?|liters?|cloves?|stalks?|slices?|cans?|packages?|heads?|handfuls?|pinches?|dashes?|sprigs?|bunches?|sticks?|jars?|bottles?|sheets?|pieces?)\b\s*(.*)$"#,
        options: [.caseInsensitive]
    )
    private static let secondMeasure = try! NSRegularExpression(
        pattern: #"\s*(?:plus|and)\s+(?=(?:(?:\d+\s+)?(?:\d+\s*/\s*\d+|\d+(?:[.,]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]))\b)"#,
        options: [.caseInsensitive]
    )

    static func columns(for ingredient: NormalizedRecipeIngredientText) -> NormalizedRecipeColumns {
        NormalizedRecipeColumns(quantity: clean(ingredient.amount), ingredient: join(ingredient.unit, ingredient.description))
    }

    /// Repairs the earlier Safari export layout that put units or package text
    /// beside the number in Quantity. Source recipe Markdown keeps those words
    /// at the start of Ingredient.
    static func repairImportedColumns(quantity rawQuantity: String, ingredient rawIngredient: String) -> NormalizedRecipeColumns {
        let quantity = clean(rawQuantity)
        let ingredient = clean(rawIngredient)
        guard let match = match(amountWithUnit, in: quantity),
              let amountRange = Range(match.range(at: 1), in: quantity),
              let remainderRange = Range(match.range(at: 2), in: quantity) else {
            return NormalizedRecipeColumns(quantity: quantity, ingredient: ingredient)
        }
        let amount = clean(String(quantity[amountRange]))
        guard amountOnly.firstMatch(in: amount, range: NSRange(amount.startIndex..., in: amount)) != nil else {
            return NormalizedRecipeColumns(quantity: quantity, ingredient: ingredient)
        }
        let unitAndDescription = clean(String(quantity[remainderRange]))
        return NormalizedRecipeColumns(quantity: amount, ingredient: join(unitAndDescription, ingredient))
    }

    static func markdownRow(for columns: NormalizedRecipeColumns) -> String {
        "| \(markdownCell(columns.quantity)) | \(markdownCell(columns.ingredient)) |"
    }

    /// Repairs common LLM field-placement mistakes, then splits a clearly marked
    /// second measurement into its own recipe row. It never splits bare prose.
    static func normalize(amount rawAmount: String, unit rawUnit: String, description rawDescription: String, splitMultipleMeasurements: Bool = true) -> [NormalizedRecipeIngredientText] {
        var amount = clean(rawAmount)
        var unitText = clean(rawUnit)
        var description = clean(rawDescription)

        if !amount.isEmpty, match(amountOnly, in: amount) == nil,
           let match = match(amountWithUnit, in: amount),
           let numberRange = Range(match.range(at: 1), in: amount),
           let trailingRange = Range(match.range(at: 2), in: amount) {
            let originalAmount = amount
            amount = clean(String(amount[numberRange]))
            let trailing = clean(String(originalAmount[trailingRange]))
            if unitText.isEmpty {
                if let unitMatch = matchUnit(in: trailing) {
                    unitText = unitMatch.unit
                    if !unitMatch.remainder.isEmpty { description = join(unitMatch.remainder, description) }
                } else {
                    unitText = trailing
                }
            } else {
                let trailingUnit = matchUnit(in: trailing)
                if trailing.caseInsensitiveCompare(unitText) != .orderedSame {
                    if let trailingUnit, trailingUnit.unit.caseInsensitiveCompare(unitText) == .orderedSame {
                        description = join(trailingUnit.remainder, description)
                    } else {
                        description = join(trailing, description)
                    }
                }
            }
        } else if !amount.isEmpty, match(amountOnly, in: amount) == nil {
            let phrase = amount
            amount = ""
            if unitText.isEmpty {
                if ["to taste", "as needed", "as desired"].contains(phrase.lowercased()) {
                    description = join(description, phrase)
                } else {
                    unitText = phrase
                }
            } else {
                description = join(phrase, description)
            }
        }

        if description.isEmpty, !unitText.isEmpty {
            if let parsed = parseLeadingMeasure(unitText) {
                amount = parsed.amount
                unitText = parsed.unit
                description = parsed.description
            } else if let parsed = matchUnit(in: unitText), !parsed.remainder.isEmpty {
                unitText = parsed.unit
                description = parsed.remainder
            }
        }

        if amount.isEmpty, unitText.isEmpty, let parsed = parseLeadingMeasure(description) {
            amount = parsed.amount
            unitText = parsed.unit
            description = parsed.description
        }

        if unitText.isEmpty, let parsed = matchUnit(in: description) {
            unitText = parsed.unit
            description = parsed.remainder
        }

        let normalized = NormalizedRecipeIngredientText(amount: amount, unit: unitText, description: description)
        guard splitMultipleMeasurements else { return [normalized] }
        guard let match = match(secondMeasure, in: description),
              let boundary = Range(match.range, in: description) else { return [normalized] }

        let firstDescription = clean(String(description[..<boundary.lowerBound]))
        let secondText = clean(String(description[boundary.upperBound...]))
        guard let second = parseLeadingMeasure(secondText), !second.description.isEmpty else { return [normalized] }

        // A phrase like "2 tablespoons plus 2 cups water" repeats the ingredient
        // only once. The trailing name therefore applies to both quantities.
        let firstName = firstDescription.isEmpty ? second.description : firstDescription
        return [
            NormalizedRecipeIngredientText(amount: amount, unit: unitText, description: firstName),
            second
        ]
    }

    static func ingredient(amount: String, unit: String, description: String) -> NormalizedRecipeIngredientText {
        normalize(amount: amount, unit: unit, description: description, splitMultipleMeasurements: false)[0]
    }

    private static func parseLeadingMeasure(_ text: String) -> NormalizedRecipeIngredientText? {
        guard let match = match(amountWithUnit, in: text),
              let amountRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 2), in: text) else { return nil }
        let rest = clean(String(text[restRange]))
        guard let parsedUnit = matchUnit(in: rest), !parsedUnit.remainder.isEmpty else { return nil }
        return NormalizedRecipeIngredientText(amount: clean(String(text[amountRange])), unit: parsedUnit.unit, description: parsedUnit.remainder)
    }

    private static func matchUnit(in text: String) -> (unit: String, remainder: String)? {
        guard let match = match(unit, in: text),
              let unitRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 2), in: text) else { return nil }
        return (clean(String(text[unitRange])), clean(String(text[restRange])))
    }

    private static func match(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func join(_ first: String, _ second: String) -> String {
        [first, second].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func markdownCell(_ value: String) -> String {
        let escapable = "\\`*_{}[]()#+-.!>|~"
        var result = ""
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
        for scalar in normalized.unicodeScalars {
            if scalar == "\n" {
                result += "<br>"
                continue
            }
            if scalar.isASCII, escapable.unicodeScalars.contains(scalar) { result.append("\\") }
            result.append(String(scalar))
        }
        return result
    }
}
