import Foundation

struct CookbookCatalog: Decodable {
    let schemaVersion: Int
    let categoryOrder: [String]
    let recipes: [Recipe]
    let labelGroups: [RecipeLabelGroup]?
    let labels: [RecipeLabel]?

    func label(matching value: String) -> RecipeLabel? {
        let target = RecipeLabel.normalize(value)
        return labels?.first { label in
            (label.aliases + [label.displayName]).contains { RecipeLabel.normalize($0) == target }
        }
    }

    static let bundled: CookbookCatalog = {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CookbookCatalog.self, from: data) else {
            return CookbookCatalog(schemaVersion: 1, categoryOrder: [], recipes: [], labelGroups: nil, labels: nil)
        }
        return catalog
    }()
}

struct Recipe: Codable, Identifiable, Hashable, Sendable {
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
    let thumbnailAsset: String?
    let labelIDs: [String]?
    let provenance: RecipeProvenance?
    let menuDescription: String?
    let menuPairings: [String]?
    let servings: String?

    var browseLabelIDs: [String] { labelIDs ?? [] }
}

struct RecipeProvenance: Codable, Hashable, Sendable {
    let type: RecipeSourceType
    let name: String?
    let reference: String?

    var tagLabel: String {
        switch type {
        case .website:
            if let reference, let host = URLComponents(string: reference)?.host {
                return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)).lowercased() : host.lowercased()
            }
            return name ?? type.displayName
        case .paprikaImport:
            return name ?? type.displayName
        case .magazinePhoto:
            return "Magazine photo"
        case .personalCookbook, .cookbookRepository:
            return "Personal cookbook"
        case .manual, .other:
            return name ?? type.displayName
        }
    }
}

enum RecipeSourceType: String, Codable, Hashable, Sendable {
    case website
    case paprikaImport
    case magazinePhoto
    case manual
    case personalCookbook
    case cookbookRepository
    case other

    var displayName: String {
        switch self {
        case .website: "Website"
        case .paprikaImport: "Paprika import"
        case .magazinePhoto: "Magazine photo"
        case .manual: "Manual entry"
        case .personalCookbook: "Personal cookbook"
        case .cookbookRepository: "Cookbook repository"
        case .other: "Other"
        }
    }
}

struct RecipeLabelGroup: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let order: Int
    let menuRole: String
    let wizardStep: Int?
    let optional: Bool
    let allowsMultiple: Bool
}

struct RecipeLabel: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let groupID: String
    let order: Int
    let aliases: [String]

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

enum RecipeLabelFilter {
    static func togglingSingle(_ label: RecipeLabel, selectedLabelIDs: Set<String>, labels: [RecipeLabel]) -> Set<String> {
        let labelsInGroup = labels.filter { $0.groupID == label.groupID }.map(\.id)
        if selectedLabelIDs.contains(label.id) {
            return selectedLabelIDs.subtracting(labelsInGroup)
        }
        return selectedLabelIDs.subtracting(labelsInGroup).union([label.id])
    }

    static func matches(_ recipe: Recipe, selectedLabelIDs: Set<String>, groups: [RecipeLabelGroup], labels: [RecipeLabel]) -> Bool {
        let recipeLabels = Set(recipe.browseLabelIDs)
        return groups.allSatisfy { group in
            let selectedInGroup = Set(labels.lazy.filter { $0.groupID == group.id && selectedLabelIDs.contains($0.id) }.map(\.id))
            return selectedInGroup.isEmpty || !recipeLabels.isDisjoint(with: selectedInGroup)
        }
    }

    static func eligibleLabels(forGroupAt groupIndex: Int, recipes: [Recipe], selectedLabelIDs: Set<String>, groups: [RecipeLabelGroup], labels: [RecipeLabel]) -> [RecipeLabel] {
        guard groups.indices.contains(groupIndex) else { return [] }
        let earlierSelections = Set(labels.filter { label in
            guard let index = groups.firstIndex(where: { $0.id == label.groupID }) else { return false }
            return index < groupIndex && selectedLabelIDs.contains(label.id)
        }.map(\.id))
        return labels
            .filter { $0.groupID == groups[groupIndex].id }
            .sorted { $0.order < $1.order }
            .filter { candidate in
                recipes.contains { recipe in
                    matches(recipe, selectedLabelIDs: earlierSelections.union([candidate.id]), groups: groups, labels: labels)
                }
            }
    }
}

struct RecipeIngredient: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let amount: String
    let unit: String
    let description: String
    let groceryName: String
    let staple: Bool
    let excludeFromGroceries: Bool
    let group: String?

    var quantity: String { amount }
    var name: String { [unit, description].filter { !$0.isEmpty }.joined(separator: " ") }

    init(id: String, quantity: String, name: String, groceryName: String, staple: Bool, excludeFromGroceries: Bool, group: String? = nil) {
        let columns = RecipeIngredientTextNormalizer.repairImportedColumns(quantity: quantity, ingredient: name)
        let normalized = RecipeIngredientTextNormalizer.ingredient(amount: columns.quantity, unit: "", description: columns.ingredient)
        self.init(id: id, amount: normalized.amount, unit: normalized.unit, description: normalized.description, groceryName: groceryName, staple: staple, excludeFromGroceries: excludeFromGroceries, group: group)
    }

    init(id: String, amount: String, unit: String, description: String, groceryName: String, staple: Bool, excludeFromGroceries: Bool, group: String? = nil) {
        let normalized = RecipeIngredientTextNormalizer.ingredient(amount: amount, unit: unit, description: description)
        self.id = id
        self.amount = normalized.amount
        self.unit = normalized.unit
        self.description = normalized.description
        self.groceryName = groceryName
        self.staple = staple
        self.excludeFromGroceries = excludeFromGroceries
        self.group = group
    }

    private enum CodingKeys: String, CodingKey {
        case id, amount, unit, description, quantity, name, groceryName, staple, excludeFromGroceries, group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let groceryName = try container.decodeIfPresent(String.self, forKey: .groceryName) ?? ""
        let staple = try container.decodeIfPresent(Bool.self, forKey: .staple) ?? false
        let excludeFromGroceries = try container.decodeIfPresent(Bool.self, forKey: .excludeFromGroceries) ?? false
        let group = try container.decodeIfPresent(String.self, forKey: .group)
        if container.contains(.amount) {
            self.init(
                id: id,
                amount: try container.decodeIfPresent(String.self, forKey: .amount) ?? "",
                unit: try container.decodeIfPresent(String.self, forKey: .unit) ?? "",
                description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
                groceryName: groceryName,
                staple: staple,
                excludeFromGroceries: excludeFromGroceries,
                group: group
            )
        } else {
            self.init(
                id: id,
                quantity: try container.decodeIfPresent(String.self, forKey: .quantity) ?? "",
                name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                groceryName: groceryName,
                staple: staple,
                excludeFromGroceries: excludeFromGroceries,
                group: group
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(amount, forKey: .amount)
        try container.encode(unit, forKey: .unit)
        try container.encode(description, forKey: .description)
        try container.encode(groceryName, forKey: .groceryName)
        try container.encode(staple, forKey: .staple)
        try container.encode(excludeFromGroceries, forKey: .excludeFromGroceries)
        try container.encodeIfPresent(group, forKey: .group)
    }
}

struct RecipeStep: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sectionTitle: String
    let instruction: String
    let originalInstruction: String
    let ingredientIDs: [String]
    let durationMinutes: Int?
    let active: Bool
}
