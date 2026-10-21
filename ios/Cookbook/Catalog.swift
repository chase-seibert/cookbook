import Foundation

struct CookbookCatalog: Decodable {
    let schemaVersion: Int
    let categoryOrder: [String]
    let recipes: [Recipe]

    static let bundled: CookbookCatalog = {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CookbookCatalog.self, from: data) else {
            return CookbookCatalog(schemaVersion: 1, categoryOrder: [], recipes: [])
        }
        return catalog
    }()
}

struct Recipe: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let collectionTitle: String?
    let sourceFile: String
    let sourceSection: String
    let introduction: String
    let ingredients: [RecipeIngredient]
    let steps: [RecipeStep]
    let tips: [String]
    let healthierOptions: [String]
}

struct RecipeIngredient: Decodable, Identifiable, Hashable {
    let id: String
    let quantity: String
    let name: String
    let groceryName: String
    let staple: Bool
    let excludeFromGroceries: Bool
}

struct RecipeStep: Decodable, Identifiable, Hashable {
    let id: String
    let sectionTitle: String
    let instruction: String
    let originalInstruction: String
    let ingredientIDs: [String]
    let durationMinutes: Int?
    let active: Bool
}
