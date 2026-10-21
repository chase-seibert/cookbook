import Foundation
import SwiftData

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
