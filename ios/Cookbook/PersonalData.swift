import Foundation
import SwiftData

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
