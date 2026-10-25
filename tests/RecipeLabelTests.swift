import Foundation

@main
struct RecipeLabelTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "ios/Cookbook/Resources/recipes.json"))
        let catalog = try JSONDecoder().decode(CookbookCatalog.self, from: data)
        let groups = try XCTUnwrap(catalog.labelGroups)
        let labels = try XCTUnwrap(catalog.labels)

        try require(catalog.recipes.count == 76, "expected all 76 cookbook recipes")
        try require(catalog.recipes.allSatisfy { !$0.browseLabelIDs.isEmpty }, "every recipe needs a browse label")
        try require(catalog.label(matching: "BROCCOLI RABE")?.id == "broccoli", "broccoli rabe must resolve through its reviewed alias")

        let chicken = try label("chicken", labels)
        let beef = try label("beef", labels)
        let salad = try label("salad", labels)
        let pasta = try label("pasta", labels)
        let protein = try group("protein", groups)
        let mealStyle = try group("meal-style", groups)
        let ingredient = try group("ingredient", groups)
        try require(!protein.allowsMultiple, "the wizard accepts one protein choice")

        var browserChoices = RecipeLabelFilter.togglingSingle(chicken, selectedLabelIDs: [], labels: labels)
        browserChoices = RecipeLabelFilter.togglingSingle(pasta, selectedLabelIDs: browserChoices, labels: labels)
        try require(browserChoices == ["chicken", "pasta"], "single selections in separate filter groups should combine")
        browserChoices = RecipeLabelFilter.togglingSingle(beef, selectedLabelIDs: browserChoices, labels: labels)
        try require(browserChoices == ["beef", "pasta"], "choosing a second protein should replace only the protein filter")

        let orSelection: Set<String> = [chicken.id, beef.id]
        let candidates = catalog.recipes.filter {
            RecipeLabelFilter.matches($0, selectedLabelIDs: orSelection, groups: [protein], labels: labels)
        }
        try require(candidates.contains { $0.id == "southwest" }, "multiple labels in one group should match either choice")
        try require(!candidates.contains { $0.id == "panko_mahi_mahi" }, "unselected protein should not match")

        let refined = catalog.recipes.filter {
            RecipeLabelFilter.matches($0, selectedLabelIDs: [beef.id, salad.id], groups: [protein, mealStyle], labels: labels)
        }
        try require(refined.map(\.id) == ["southwest"], "selections across groups should refine together in catalog order")

        let chickenPasta = catalog.recipes.filter {
            RecipeLabelFilter.matches($0, selectedLabelIDs: [chicken.id, pasta.id], groups: [protein, mealStyle], labels: labels)
        }
        try require(chickenPasta.contains { $0.id == "chicken_parmesan" }, "chicken plus pasta should match chicken parmesan")
        try require(!chickenPasta.contains { $0.id == "orange_chicken" }, "chicken plus pasta should refine out orange chicken")

        let fishStyles = RecipeLabelFilter.eligibleLabels(forGroupAt: 1, recipes: catalog.recipes, selectedLabelIDs: ["fish-seafood"], groups: [protein, mealStyle, ingredient], labels: labels)
        try require(fishStyles.map(\.id) == ["salad"], "meal-style choices should only include options with a matching fish recipe")
        let fishSaladIngredients = RecipeLabelFilter.eligibleLabels(forGroupAt: 2, recipes: catalog.recipes, selectedLabelIDs: ["fish-seafood", "salad"], groups: [protein, mealStyle, ingredient], labels: labels)
        try require(fishSaladIngredients.map(\.id) == ["carrots", "lentils", "cheese", "lemon"], "ingredient choices should reflect the selected protein and meal style")
        let turkeyStyles = RecipeLabelFilter.eligibleLabels(forGroupAt: 1, recipes: catalog.recipes, selectedLabelIDs: ["turkey"], groups: [protein, mealStyle, ingredient], labels: labels)
        try require(turkeyStyles.isEmpty, "a phase with no matching choices should be skippable")
        let turkeyIngredients = RecipeLabelFilter.eligibleLabels(forGroupAt: 2, recipes: catalog.recipes, selectedLabelIDs: ["turkey"], groups: [protein, mealStyle, ingredient], labels: labels)
        try require(!turkeyIngredients.isEmpty, "ingredient discovery should remain available after an empty meal-style phase")

        let mahi = try XCTUnwrap(catalog.recipes.first(where: { $0.id == "panko_mahi_mahi" }))
        try require(mahi.thumbnailAsset == "panko_mahi_mahi.jpg", "the reviewed mahi-mahi thumbnail override should restore its photo")
        try require(mahi.menuDescription?.contains("mahi-mahi") == true, "reviewed menu description should be present in generated catalog")
        try require(mahi.menuPairings?.count == 2, "reviewed menu pairings should be present in generated catalog")

        let oldData = Data(#"{"schemaVersion":1,"categoryOrder":[],"recipes":[{"id":"old","title":"Old","category":"Old","sourceFile":"old.tex","sourceSection":"Old","introduction":"","ingredients":[],"steps":[],"tips":[],"healthierOptions":[]}]}"#.utf8)
        let oldCatalog = try JSONDecoder().decode(CookbookCatalog.self, from: oldData)
        try require(oldCatalog.labelGroups == nil && oldCatalog.labels == nil, "legacy catalogs without taxonomy should decode")
        try require(oldCatalog.recipes[0].browseLabelIDs.isEmpty, "legacy recipes without label IDs should decode")
        try require(oldCatalog.recipes[0].menuDescription == nil && oldCatalog.recipes[0].menuPairings == nil, "legacy recipes without menu copy should decode")
        print("Recipe label model and filter checks passed")
    }

    static func label(_ id: String, _ labels: [RecipeLabel]) throws -> RecipeLabel {
        guard let value = labels.first(where: { $0.id == id }) else { throw TestFailure(message: "missing label \(id)") }
        return value
    }

    static func group(_ id: String, _ groups: [RecipeLabelGroup]) throws -> RecipeLabelGroup {
        guard let value = groups.first(where: { $0.id == id }) else { throw TestFailure(message: "missing group \(id)") }
        return value
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message: message) }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else { throw TestFailure(message: "unexpected nil at \(file):\(line)") }
    return value
}
