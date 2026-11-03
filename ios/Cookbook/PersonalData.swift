import Foundation
import SwiftData

@Model final class RecipeCategory {
    @Attribute(.unique) var id: String
    var name: String
    var order: Int
    var aliasesData: Data

    init(id: String, name: String, order: Int, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.order = order
        aliasesData = (try? JSONEncoder().encode(aliases)) ?? Data("[]".utf8)
    }

    var aliases: [String] { (try? JSONDecoder().decode([String].self, from: aliasesData)) ?? [] }
}

@Model final class RecipeCategorySettings {
    @Attribute(.unique) var id: String
    var defaultCategoryID: String

    init(defaultCategoryID: String, id: String = "settings") {
        self.id = id
        self.defaultCategoryID = defaultCategoryID
    }
}

@Model final class RecipeCategoryAssignment {
    @Attribute(.unique) var recipeID: String
    var categoryID: String

    init(recipeID: String, categoryID: String) {
        self.recipeID = recipeID
        self.categoryID = categoryID
    }
}

enum RecipeCategoryStore {
    static let fallbackID = "cookbook:general"

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func stableID(for name: String) -> String {
        "catalog:" + normalized(name).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    static func match(sourceNames: [String], categories: [RecipeCategory]) -> RecipeCategory? {
        let keys = Set(sourceNames.map(normalized).filter { !$0.isEmpty })
        let matches = categories.filter { category in
            keys.contains(normalized(category.name)) || category.aliases.contains(where: { keys.contains(normalized($0)) })
        }
        return matches.count == 1 ? matches[0] : nil
    }

    @MainActor static func seedIfNeeded(in context: ModelContext) throws {
        var categories = try context.fetch(FetchDescriptor<RecipeCategory>())
        if categories.isEmpty {
            let names = CookbookCatalog.bundled.categoryOrder.isEmpty ? ["General"] : CookbookCatalog.bundled.categoryOrder
            categories = names.enumerated().map { index, name in
                let category = RecipeCategory(id: stableID(for: name), name: name, order: index)
                context.insert(category)
                return category
            }
        }
        let settings = try context.fetch(FetchDescriptor<RecipeCategorySettings>()).first
        let selectedDefault = categories.first(where: { $0.id == settings?.defaultCategoryID }) ?? categories.sorted(by: { $0.order < $1.order }).first!
        if let settings {
            settings.defaultCategoryID = selectedDefault.id
        } else {
            context.insert(RecipeCategorySettings(defaultCategoryID: selectedDefault.id))
        }

        let assignments = try context.fetch(FetchDescriptor<RecipeCategoryAssignment>())
        let assignedIDs = Set(assignments.map(\.recipeID))
        let imported = try context.fetch(FetchDescriptor<ImportedPaprikaRecipe>())
        let webImported = try context.fetch(FetchDescriptor<ImportedWebRecipe>())
        let magazineImported = try context.fetch(FetchDescriptor<ImportedMagazineRecipe>())
        let recipes = CookbookCatalog.bundled.recipes + imported.compactMap(\.recipe) + webImported.compactMap(\.recipe) + magazineImported.compactMap(\.recipe)
        for recipe in recipes where !assignedIDs.contains(recipe.id) {
            let category = match(sourceNames: [recipe.category], categories: categories) ?? selectedDefault
            context.insert(RecipeCategoryAssignment(recipeID: recipe.id, categoryID: category.id))
        }
        try context.save()
    }

    @MainActor static func setAssignment(recipeID: String, categoryID: String, in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<RecipeCategory>())
        guard categories.contains(where: { $0.id == categoryID }) else { throw RecipeCategoryError.missingCategory }
        let descriptor = FetchDescriptor<RecipeCategoryAssignment>(predicate: #Predicate { $0.recipeID == recipeID })
        if let assignment = try context.fetch(descriptor).first { assignment.categoryID = categoryID }
        else { context.insert(RecipeCategoryAssignment(recipeID: recipeID, categoryID: categoryID)) }
        try context.save()
    }

    @MainActor static func deleteCategory(_ categoryID: String, replacingWith replacementID: String?, in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<RecipeCategory>()).sorted { $0.order < $1.order }
        guard let category = categories.first(where: { $0.id == categoryID }) else { return }
        guard categories.count > 1 else { throw RecipeCategoryError.lastCategory }
        guard let replacementID, replacementID != categoryID, categories.contains(where: { $0.id == replacementID }) else {
            throw RecipeCategoryError.replacementRequired
        }
        let settings = try context.fetch(FetchDescriptor<RecipeCategorySettings>()).first
        let assignments = try context.fetch(FetchDescriptor<RecipeCategoryAssignment>())
        let assignmentsByID = Dictionary(uniqueKeysWithValues: assignments.map { ($0.recipeID, $0) })
        let imported = try context.fetch(FetchDescriptor<ImportedPaprikaRecipe>())
        let webImported = try context.fetch(FetchDescriptor<ImportedWebRecipe>())
        let magazineImported = try context.fetch(FetchDescriptor<ImportedMagazineRecipe>())
        let recipes = CookbookCatalog.bundled.recipes + imported.compactMap(\.recipe) + webImported.compactMap(\.recipe) + magazineImported.compactMap(\.recipe)
        try context.transaction {
            for recipe in recipes {
                let assignedID = assignmentsByID[recipe.id]?.categoryID
                    ?? Self.match(sourceNames: [recipe.category], categories: categories)?.id
                    ?? settings?.defaultCategoryID
                guard assignedID == categoryID else { continue }
                if let assignment = assignmentsByID[recipe.id] { assignment.categoryID = replacementID }
                else { context.insert(RecipeCategoryAssignment(recipeID: recipe.id, categoryID: replacementID)) }
            }
            if settings?.defaultCategoryID == categoryID { settings?.defaultCategoryID = replacementID }
            context.delete(category)
            for (index, remaining) in categories.filter({ $0.id != categoryID }).enumerated() { remaining.order = index }
        }
    }

    @MainActor static func renameCategory(_ categoryID: String, to name: String, in context: ModelContext) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RecipeCategoryError.emptyName }
        let categories = try context.fetch(FetchDescriptor<RecipeCategory>())
        guard let category = categories.first(where: { $0.id == categoryID }) else { throw RecipeCategoryError.missingCategory }
        guard !categories.contains(where: { $0.id != categoryID && normalized($0.name) == normalized(cleanName) }) else { throw RecipeCategoryError.duplicateName }
        var aliases = category.aliases
        if normalized(category.name) != normalized(cleanName), !aliases.contains(where: { normalized($0) == normalized(category.name) }) {
            aliases.append(category.name)
            category.aliasesData = (try? JSONEncoder().encode(aliases)) ?? Data("[]".utf8)
        }
        category.name = cleanName
        try context.save()
    }
}

enum RecipeCategoryError: LocalizedError {
    case missingCategory
    case replacementRequired
    case lastCategory
    case emptyName
    case duplicateName
    var errorDescription: String? {
        switch self {
        case .missingCategory: "That category is no longer available. Choose an existing category."
        case .replacementRequired: "Choose an existing category to receive these recipes."
        case .lastCategory: "Cookbook must have at least one category."
        case .emptyName: "Enter a category name."
        case .duplicateName: "A category with that name already exists."
        }
    }
}

@Model final class ImportedPaprikaRecipe {
    @Attribute(.unique) var id: String
    var paprikaUID: String
    var recipeData: Data
    var importedAt: Date
    var paprikaImportRunID: String?
    var deletedAt: Date?

    init(id: String, paprikaUID: String, recipeData: Data, importedAt: Date = .now, paprikaImportRunID: String? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.paprikaUID = paprikaUID
        self.recipeData = recipeData
        self.importedAt = importedAt
        self.paprikaImportRunID = paprikaImportRunID
        self.deletedAt = deletedAt
    }

    var recipe: Recipe? { try? JSONDecoder().decode(Recipe.self, from: recipeData) }
}

@Model final class ImportedWebRecipe {
    @Attribute(.unique) var id: String
    var recipeData: Data
    var sourceURL: String
    var capturedAt: Date
    var editedAt: Date
    var deletedAt: Date?

    init(id: String, recipeData: Data, sourceURL: String, capturedAt: Date = .now, editedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id
        self.recipeData = recipeData
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
    }

    var recipe: Recipe? {
        guard let recipe = try? JSONDecoder().decode(Recipe.self, from: recipeData) else { return nil }
        return WebRecipeIngredientNormalizer.repairLegacyColumns(in: recipe)
    }
}

@Model final class ImportedMagazineRecipe {
    @Attribute(.unique) var id: String
    var recipeData: Data
    var capturedAt: Date
    var deletedAt: Date?

    init(id: String, recipeData: Data, capturedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id
        self.recipeData = recipeData
        self.capturedAt = capturedAt
        self.deletedAt = deletedAt
    }

    var recipe: Recipe? { try? JSONDecoder().decode(Recipe.self, from: recipeData) }
}

@Model final class PaprikaImportRun {
    @Attribute(.unique) var id: String
    var dayKey: String
    var runNumber: Int
    var labelID: String
    var createdAt: Date
    var importedRecipeIDsData: Data
    var skippedRecipesData: Data
    var importedCount: Int
    var skippedCount: Int
    var undoneAt: Date?

    init(id: String, dayKey: String, runNumber: Int, labelID: String, createdAt: Date = .now, importedRecipeIDsData: Data, skippedRecipesData: Data, importedCount: Int, skippedCount: Int, undoneAt: Date? = nil) {
        self.id = id
        self.dayKey = dayKey
        self.runNumber = runNumber
        self.labelID = labelID
        self.createdAt = createdAt
        self.importedRecipeIDsData = importedRecipeIDsData
        self.skippedRecipesData = skippedRecipesData
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.undoneAt = undoneAt
    }

    var importedRecipeIDs: [String] { (try? JSONDecoder().decode([String].self, from: importedRecipeIDsData)) ?? [] }
    var skippedRecipes: [PaprikaSkippedRecipe] { (try? JSONDecoder().decode([PaprikaSkippedRecipe].self, from: skippedRecipesData)) ?? [] }
    var displayName: String { "Paprika file · \(createdAt.formatted(date: .abbreviated, time: .shortened)) · run \(runNumber)" }
}

@Model final class DeletedRecipe {
    @Attribute(.unique) var recipeID: String
    var deletedAt: Date

    init(recipeID: String, deletedAt: Date = .now) {
        self.recipeID = recipeID
        self.deletedAt = deletedAt
    }
}

struct PaprikaSkippedRecipe: Codable, Hashable, Identifiable, Sendable {
    let uid: String
    let title: String
    let reason: String
    var id: String { uid }
}

@Model final class RecipeNote {
    @Attribute(.unique) var id: UUID
    var recipeID: String
    var stepID: String?
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var catalogHash: String
    var deletedAt: Date?

    init(recipeID: String, stepID: String? = nil, text: String, catalogHash: String = "") {
        id = UUID()
        self.recipeID = recipeID
        self.stepID = stepID
        self.text = text
        createdAt = .now
        updatedAt = .now
        self.catalogHash = catalogHash
    }
}

@Model final class CookingSessionRecord {
    @Attribute(.unique) var recipeID: String
    var stepID: String
    var sectionProgressData: Data
    var updatedAt: Date
    init(recipeID: String, stepID: String) { self.recipeID = recipeID; self.stepID = stepID; sectionProgressData = Data("{}".utf8); updatedAt = .now }
    var sectionProgress: [String: String] { (try? JSONDecoder().decode([String: String].self, from: sectionProgressData)) ?? [:] }
}

@Model final class RecipePhoto {
    @Attribute(.unique) var id: UUID
    var recipeID: String
    var relativePath: String
    var createdAt: Date
    var isCover: Bool

    init(recipeID: String, relativePath: String, isCover: Bool = false) {
        id = UUID()
        self.recipeID = recipeID
        self.relativePath = relativePath
        createdAt = .now
        self.isCover = isCover
    }
}

@Model final class ImageGenerationRun {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var provider: String
    var model: String
    var status: String
    var isBulk: Bool
    var recipeCount: Int
    var completedCount: Int
    var failedCount: Int

    init(id: UUID = UUID(), createdAt: Date = .now, provider: String, model: String, status: String = "running", isBulk: Bool = false, recipeCount: Int, completedCount: Int = 0, failedCount: Int = 0) {
        self.id = id; self.createdAt = createdAt; self.provider = provider; self.model = model
        self.status = status; self.isBulk = isBulk; self.recipeCount = recipeCount; self.completedCount = completedCount; self.failedCount = failedCount
    }
}

@Model final class ImageGenerationEntry {
    @Attribute(.unique) var id: UUID
    var runID: UUID
    var recipeID: String
    var status: String
    var generatedPhotoID: String?
    var previousPhotoID: String?
    var previousBundledAsset: String?
    var previousHadNoImage: Bool
    var errorMessage: String?

    init(id: UUID = UUID(), runID: UUID, recipeID: String, status: String = "pending", generatedPhotoID: String? = nil, previousPhotoID: String? = nil, previousBundledAsset: String? = nil, previousHadNoImage: Bool = false, errorMessage: String? = nil) {
        self.id = id; self.runID = runID; self.recipeID = recipeID; self.status = status
        self.generatedPhotoID = generatedPhotoID; self.previousPhotoID = previousPhotoID
        self.previousBundledAsset = previousBundledAsset; self.previousHadNoImage = previousHadNoImage
        self.errorMessage = errorMessage
    }
}

@Model final class DinnerTimeline {
    @Attribute(.unique) var id: UUID
    var name: String
    var targetDate: Date
    var recipeIDsData: Data
    var activitiesData: Data
    var updatedAt: Date

    init(name: String, targetDate: Date, recipeIDs: [String], activities: [TimelineActivity]) {
        id = UUID(); self.name = name; self.targetDate = targetDate
        recipeIDsData = (try? JSONEncoder().encode(recipeIDs)) ?? Data()
        activitiesData = (try? JSONEncoder().encode(activities)) ?? Data()
        updatedAt = .now
    }
    var activities: [TimelineActivity] { (try? JSONDecoder().decode([TimelineActivity].self, from: activitiesData)) ?? [] }
}

@Model final class PlannedDinnerRecipe {
    @Attribute(.unique) var id: UUID
    var recipeID: String
    var dinnerDate: Date
    var addedAt: Date

    init(recipeID: String, dinnerDate: Date) {
        id = UUID(); self.recipeID = recipeID; self.dinnerDate = dinnerDate; addedAt = .now
    }
}

@Model final class RecipeUsageStats {
    @Attribute(.unique) var recipeID: String
    var recipeOpenCount: Int
    var groceryAddFlowCount: Int
    var updatedAt: Date

    init(recipeID: String, recipeOpenCount: Int = 0, groceryAddFlowCount: Int = 0, updatedAt: Date = .now) {
        self.recipeID = recipeID
        self.recipeOpenCount = recipeOpenCount
        self.groceryAddFlowCount = groceryAddFlowCount
        self.updatedAt = updatedAt
    }
}

@MainActor struct RecipeUsageStore {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func recordRecipeOpen(_ recipeID: String) {
        update(recipeID) { $0.recipeOpenCount += 1 }
    }

    func recordCompletedGroceryFlow(_ recipeID: String) {
        update(recipeID) { $0.groceryAddFlowCount += 1 }
    }

    private func update(_ recipeID: String, change: (RecipeUsageStats) -> Void) {
        let descriptor = FetchDescriptor<RecipeUsageStats>(predicate: #Predicate<RecipeUsageStats> { $0.recipeID == recipeID })
        let stats: RecipeUsageStats
        if let existing = try? context.fetch(descriptor).first {
            stats = existing
        } else {
            stats = RecipeUsageStats(recipeID: recipeID)
            context.insert(stats)
        }
        change(stats)
        stats.updatedAt = .now
        do { try context.save() }
        catch { print("Could not save recipe usage statistics: \(error.localizedDescription)") }
    }
}

struct TimelineActivity: Codable, Identifiable {
    var id: String
    var recipeTitle: String
    var instruction: String
    var start: Date
    var end: Date
    var active: Bool
    var estimateLabel: String
    var isComplete: Bool = false

    private enum CodingKeys: String, CodingKey { case id, recipeTitle, instruction, start, end, active, estimateLabel, isComplete }

    init(id: String, recipeTitle: String, instruction: String, start: Date, end: Date, active: Bool, estimateLabel: String, isComplete: Bool = false) {
        self.id = id; self.recipeTitle = recipeTitle; self.instruction = instruction
        self.start = start; self.end = end; self.active = active
        self.estimateLabel = estimateLabel; self.isComplete = isComplete
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        recipeTitle = try values.decode(String.self, forKey: .recipeTitle)
        instruction = try values.decode(String.self, forKey: .instruction)
        start = try values.decode(Date.self, forKey: .start)
        end = try values.decode(Date.self, forKey: .end)
        active = try values.decode(Bool.self, forKey: .active)
        estimateLabel = try values.decode(String.self, forKey: .estimateLabel)
        isComplete = try values.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
    }
}

enum UserFiles {
    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = root.appendingPathComponent("Cookbook", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func url(for relativePath: String) -> URL { directory.appendingPathComponent(relativePath) }
}
