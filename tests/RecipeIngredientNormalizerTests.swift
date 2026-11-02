import Foundation

@main
struct RecipeIngredientNormalizerTests {
    static func main() throws {
        try normalizedLLMFieldsFollowTheCookbookSchema()
        try legacyMarkdownRowsMatchTheFullChiliRecipe()
        try ingredientCodableSchemaStoresAmountUnitAndDescription()
        print("Recipe ingredient schema, chili regression, and Markdown checks passed")
    }

    private static func normalizedLLMFieldsFollowTheCookbookSchema() throws {
        let inputs = [
            RecipeIngredientTextNormalizer.normalize(amount: "2", unit: "pounds", description: "85 percent lean ground beef"),
            RecipeIngredientTextNormalizer.normalize(amount: "2 pounds", unit: "", description: "85 percent lean ground beef"),
            RecipeIngredientTextNormalizer.normalize(amount: "2", unit: "", description: "pounds 85 percent lean ground beef"),
            RecipeIngredientTextNormalizer.normalize(amount: "2", unit: "tablespoons", description: "water plus 2 cups water")
        ]
        let rows = inputs.flatMap { $0 }.map(RecipeIngredientTextNormalizer.columns)
        try require(rows[0] == NormalizedRecipeColumns(quantity: "2", ingredient: "pounds 85 percent lean ground beef"), "amount and unit must be separate in the saved schema")
        try require(rows[0] == rows[1] && rows[0] == rows[2], "the three common LLM field layouts should normalize identically")
        try require(rows[3] == NormalizedRecipeColumns(quantity: "2", ingredient: "tablespoons water"), "the first water measurement should use a numeric-only Quantity cell")
        try require(rows[4] == NormalizedRecipeColumns(quantity: "2", ingredient: "cups water"), "the second water measurement should use a numeric-only Quantity cell")
        try require(RecipeIngredientTextNormalizer.markdownRow(for: rows[0]) == "| 2 | pounds 85 percent lean ground beef |", "the chili beef row should match the source recipe convention")

        let mixedFraction = RecipeIngredientTextNormalizer.ingredient(amount: "1½", unit: "tablespoons", description: "brown sugar")
        try require(RecipeIngredientTextNormalizer.columns(for: mixedFraction).quantity == "1½", "a mixed Unicode fraction remains a numeric amount")
        let range = RecipeIngredientTextNormalizer.ingredient(amount: "1¾–2", unit: "lb", description: "mahi-mahi")
        try require(RecipeIngredientTextNormalizer.columns(for: range).quantity == "1¾–2", "a Unicode fractional range remains a numeric amount")
        let nonnumericAmount = RecipeIngredientTextNormalizer.ingredient(amount: "some", unit: "teaspoons", description: "salt")
        try require(nonnumericAmount.amount.isEmpty && nonnumericAmount.description.contains("some"), "nonnumeric amount text must never enter the amount field or be discarded")
    }

    private static func legacyMarkdownRowsMatchTheFullChiliRecipe() throws {
        let fixtureURL = URL(fileURLWithPath: "tests/fixtures/Best-Ground-Beef-Chili-imported.md")
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let ingredientSection = fixture.components(separatedBy: "## Ingredients").dropFirst().first?.components(separatedBy: "## Instructions").first ?? ""
        let actual = ingredientSection.split(whereSeparator: \.isNewline).compactMap { rawLine -> NormalizedRecipeColumns? in
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|"), !line.contains("|---|"), line != "| Quantity | Ingredient |" else { return nil }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count >= 4 else { return nil }
            return RecipeIngredientTextNormalizer.repairImportedColumns(quantity: String(cells[1]), ingredient: String(cells[2]))
        }

        let expected = [
            ("2", "pounds 85 percent lean ground beef"),
            ("2", "tablespoons water"),
            ("2", "cups water"),
            ("1 1/2", "teaspoons table salt"),
            ("2", "teaspoons pepper"),
            ("3/4", "teaspoon baking soda"),
            ("6", "dried ancho chiles, stemmed, seeded, and torn into 1\\-inch pieces"),
            ("1", "ounce tortilla chips, crushed"),
            ("2", "tablespoons ground cumin"),
            ("1", "tablespoon paprika"),
            ("1", "tablespoon garlic powder"),
            ("1", "tablespoon ground coriander"),
            ("2", "teaspoons dried oregano"),
            ("1/2", "teaspoon dried thyme"),
            ("1", "14\\.5\\-ounce can whole peeled tomatoes"),
            ("1", "tablespoon vegetable oil"),
            ("1", "onion chopped fine"),
            ("3", "cloves garlic, minced"),
            ("1 to 2", "teaspoons minced canned chipotle chile in adobo sauce"),
            ("1", "15\\-ounce can pinto beans"),
            ("2", "teaspoons sugar"),
            ("2", "tablespoons cider vinegar"),
            ("", "Lime wedge"),
            ("", "Coarsely chopped cilantro"),
            ("", "Chopped red onion")
        ].map { NormalizedRecipeColumns(quantity: $0.0, ingredient: $0.1) }

        try require(actual == expected, "all 25 chili rows should normalize; actual=\(actual), expected=\(expected)")
        let exported = actual.map(RecipeIngredientTextNormalizer.markdownRow)
        try require(exported[0] == "| 2 | pounds 85 percent lean ground beef |", "the first chili export row must keep pounds in Ingredient")
        try require(exported[1] == "| 2 | tablespoons water |", "the second chili export row must keep tablespoons in Ingredient")
        try require(exported[2] == "| 2 | cups water |", "the third chili export row must keep cups in Ingredient")
    }

    private static func ingredientCodableSchemaStoresAmountUnitAndDescription() throws {
        let ingredient = RecipeIngredient(id: "beef", quantity: "2 pounds", name: "85 percent lean ground beef", groceryName: "85 percent lean ground beef", staple: false, excludeFromGroceries: false)
        try require(ingredient.amount == "2" && ingredient.unit == "pounds" && ingredient.description == "85 percent lean ground beef", "legacy constructors must normalize into the structured schema")

        let encoded = try JSONEncoder().encode(ingredient)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        try require(object?["amount"] as? String == "2" && object?["unit"] as? String == "pounds" && object?["description"] as? String == "85 percent lean ground beef", "saved recipe ingredients must persist separate amount, unit, and description fields")
        try require(object?["quantity"] == nil && object?["name"] == nil, "the stored ingredient schema must not persist ambiguous combined columns")

        let legacy = Data(#"{"id":"legacy","quantity":"2 tablespoons","name":"water","groceryName":"water","staple":false,"excludeFromGroceries":false}"#.utf8)
        let decoded = try JSONDecoder().decode(RecipeIngredient.self, from: legacy)
        try require(decoded.amount == "2" && decoded.unit == "tablespoons" && decoded.description == "water", "legacy database payloads must migrate to separate fields when decoded")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }
}

private struct Failure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
