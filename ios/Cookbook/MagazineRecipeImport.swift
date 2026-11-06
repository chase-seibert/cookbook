import Foundation
import SwiftUI
import SwiftData
import UIKit

enum MagazineRecipeImage {
    static let maximumUploadBytes = 8 * 1_024 * 1_024

    static func prepare(_ image: UIImage) -> Data? {
        let longestSide: CGFloat = 2_200
        let scale = min(1, longestSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [0.82, 0.68, 0.52, 0.38] {
            if let data = normalized.jpegData(compressionQuality: quality), data.count <= maximumUploadBytes { return data }
        }
        return nil
    }
}

enum MagazineRecipeExtractor {
    static func extract(imageData: Data, model: String, key: String) async throws -> WebRecipeImportDraft {
        guard !key.isEmpty else { throw WebRecipeImportError.missingKey }
        guard imageData.count <= MagazineRecipeImage.maximumUploadBytes,
              let image = UIImage(data: imageData), let jpeg = image.jpegData(compressionQuality: 0.88),
              jpeg.count <= MagazineRecipeImage.maximumUploadBytes else {
            throw WebRecipeImportError.requestTooLarge
        }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": [
                "title": ["type": "string"], "introduction": ["type": "string"], "servings": ["type": "string"],
                "blocks": ["type": "array", "items": ["type": "object", "additionalProperties": false,
                    "properties": ["type": ["type": "string", "enum": ["ingredientGroup", "instruction"]], "title": ["type": ["string", "null"]],
                        "ingredients": ["type": "array", "items": ["type": "object", "additionalProperties": false,
                            "properties": ["amount": ["type": "string"], "unit": ["type": "string"], "description": ["type": "string"], "group": ["type": "string"]], "required": ["amount", "unit", "description", "group"]]],
                        "instruction": ["type": ["string", "null"]]], "required": ["type", "title", "ingredients", "instruction"]]]
            ], "required": ["title", "introduction", "servings", "blocks"]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "store": false, "max_output_tokens": 10000,
            "instructions": "Read the single recipe in this image. Extract only visible information. Return ordered blocks interleaving ingredientGroup and instruction blocks when the printed layout makes order clear; if ambiguous, put all ingredient groups before instruction blocks. Keep each ingredient group separate, including untitled groups. Preserve wording and do not guess. Each instruction block has one instruction, title=null, ingredients=[], instruction=text. Each ingredientGroup has an optional title, its ingredient rows, and instruction=null. Ingredients have separate amount, unit, description, and group fields. Preserve fraction forms exactly, including 2½, 2 ½, and 2 1/2. Use an empty amount when no quantity is printed.",
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": "Extract this printed recipe for an editable review."],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())", "detail": "high"]
            ]]],
            "text": ["format": ["type": "json_schema", "name": "magazine_recipe", "strict": true, "schema": schema]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebRecipeImportError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"].flatMap { ($0 as? [String: Any])?["message"] as? String } ?? "Check the key, model, quota, and network connection."
            throw WebRecipeImportError.http(http.statusCode, detail)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["status"] as? String == "completed", let output = root["output"] as? [[String: Any]] else {
            throw WebRecipeImportError.incompleteResponse
        }
        let text = output.lazy.filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .first { $0["type"] as? String == "output_text" }?["text"] as? String
        guard let text, let json = text.data(using: .utf8), let draft = try? JSONDecoder().decode(WebRecipeImportDraft.self, from: json) else {
            throw WebRecipeImportError.invalidResponse
        }
        let normalized = WebRecipeImportDraft(
            title: draft.title,
            introduction: draft.introduction,
            servings: draft.servings,
            blocks: draft.blocks.map { block in
                WebRecipeImportDraft.ContentBlock(type: block.type, title: block.title, ingredients: block.ingredients.flatMap { item in
                    RecipeIngredientTextNormalizer.normalize(amount: item.amount, unit: item.unit, description: item.description).map {
                        WebRecipeImportDraft.Ingredient(amount: $0.amount, unit: $0.unit, description: $0.description, group: item.group)
                    }
                }, instruction: block.instruction)
            }
        )
        try WebRecipeExtractor.validate(normalized)
        return normalized
    }
}

private struct MagazineIngredientEdit: Identifiable {
    let id: UUID
    var amount: String
    var name: String
    var group: String
}

struct MagazineRecipeImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecipeCategory.order) private var categories: [RecipeCategory]
    let imageData: Data
    let capturedAt: Date
    let model: String
    @State private var title = ""
    @State private var introduction = ""
    @State private var servings = ""
    @State private var ingredients: [MagazineIngredientEdit] = []
    @State private var instructions = ""
    @State private var contentTemplate: [RecipeImportContentTemplate] = []
    @State private var isExtracting = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedRecipe: Recipe?

    var body: some View {
        NavigationStack {
            Group {
                if let savedRecipe {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 46)).foregroundStyle(.green)
                        Text("Saved to Recipes").font(.title2.bold())
                        Text(savedRecipe.title).multilineTextAlignment(.center)
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }.padding(28)
                } else if isExtracting {
                    RecipeImportLoadingStatus(context: "Extracting your magazine photo. AI is organizing the ingredients and steps; this usually takes about 10–20 seconds.")
                } else if let recipe = makeRecipe(id: "magazine:preview") {
                    RecipeDetailView(recipe: recipe, previewOnly: true)
                } else {
                    ContentUnavailableView("Recipe Preview Unavailable", systemImage: "text.page", description: Text("Cookbook could not build a complete recipe preview from this photo."))
                }
            }
            .navigationTitle(savedRecipe == nil ? (isExtracting ? "Import Recipe" : "Review Recipe") : "Recipe Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if savedRecipe == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    if !isExtracting {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isSaving ? "Saving…" : "Save") { save() }.disabled(isSaving || makeRecipe(id: "magazine:preview") == nil)
                        }
                    }
                }
            }
            .task { await extract() }
            .alert("Magazine recipe import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Try Again") { errorMessage = nil; isExtracting = true; Task { await extract() } }
                Button("Cancel Import", role: .cancel) { dismiss() }
            } message: { Text(errorMessage ?? "") }
        }
    }

    @MainActor private func extract() async {
        do {
            let draft = try await MagazineRecipeExtractor.extract(imageData: imageData, model: model, key: KeychainKey.read())
            title = draft.title
            introduction = draft.introduction
            servings = draft.servings
            var edits: [MagazineIngredientEdit] = []
            var template: [RecipeImportContentTemplate] = []
            var instructionIndex = 0
            for block in draft.blocks {
                if block.type == "ingredientGroup" {
                    let groupEdits = block.ingredients.map { MagazineIngredientEdit(id: UUID(), amount: $0.amount, name: WebRecipeIngredientNormalizer.ingredient(unit: $0.unit, description: $0.description), group: $0.group) }
                    edits.append(contentsOf: groupEdits)
                    template.append(.ingredientGroup(title: block.title, ingredientIDs: groupEdits.map(\.id)))
                } else if block.type == "instruction" {
                    template.append(.instruction(index: instructionIndex))
                    instructionIndex += 1
                }
            }
            ingredients = edits
            contentTemplate = template
            instructions = draft.instructions.joined(separator: "\n")
        } catch { errorMessage = error.localizedDescription }
        isExtracting = false
    }

    private func makeRecipe(id: String) -> Recipe? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipeIngredients = ingredients.compactMap { item -> RecipeIngredient? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let group = item.group.trimmingCharacters(in: .whitespacesAndNewlines)
            return RecipeIngredient(id: item.id.uuidString, quantity: item.amount.trimmingCharacters(in: .whitespacesAndNewlines), name: name, groceryName: name, staple: false, excludeFromGroceries: false, group: group.isEmpty ? nil : group)
        }
        let instructionLines = instructions.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let validationDraft = WebRecipeImportDraft(
            title: cleanedTitle,
            introduction: introduction,
            servings: servings,
            blocks: [WebRecipeImportDraft.ContentBlock(type: "ingredientGroup", title: nil, ingredients: ingredients.map { WebRecipeImportDraft.Ingredient(amount: $0.amount, unit: "", description: $0.name, group: $0.group) }, instruction: nil),
                     WebRecipeImportDraft.ContentBlock(type: "instruction", title: nil, ingredients: [], instruction: "validation")]
        )
        guard (try? WebRecipeExtractor.validate(validationDraft)) != nil else { return nil }
        let steps = instructionLines
            .enumerated().map { index, line in RecipeStep(id: "step-\(index + 1)", sectionTitle: "", instruction: line, originalInstruction: line, ingredientIDs: [], durationMinutes: nil, active: true) }
        guard !cleanedTitle.isEmpty, !recipeIngredients.isEmpty, !steps.isEmpty else { return nil }
        let category = categories.sorted { $0.order < $1.order }.first?.name ?? "General"
        let ingredientsByID = Dictionary(uniqueKeysWithValues: recipeIngredients.map { ($0.id, $0) })
        var groups: [RecipeIngredientGroup] = []
        var order: [RecipeContentReference] = []
        for entry in contentTemplate {
            switch entry {
            case .ingredientGroup(let title, let ids):
                let validIDs = ids.map(\.uuidString).filter { ingredientsByID[$0] != nil }
                guard !validIDs.isEmpty else { continue }
                let groupID = "group-\(groups.count + 1)"
                groups.append(RecipeIngredientGroup(id: groupID, title: title, ingredientIDs: validIDs))
                order.append(RecipeContentReference(kind: .ingredientGroup, id: groupID))
            case .instruction(let index):
                guard steps.indices.contains(index) else { continue }
                order.append(RecipeContentReference(kind: .step, id: steps[index].id))
            }
        }
        for step in steps where !order.contains(where: { $0.id == step.id }) { order.append(RecipeContentReference(kind: .step, id: step.id)) }
        return Recipe(id: id, title: cleanedTitle, category: category, collectionTitle: nil, sourceFile: "", sourceSection: "", introduction: introduction, ingredients: recipeIngredients, ingredientGroups: groups, steps: steps, contentOrder: order, tips: [], healthierOptions: [], thumbnailAsset: nil, labelIDs: nil, provenance: RecipeProvenance(type: .magazinePhoto, name: "Magazine photo", reference: nil), menuDescription: nil, menuPairings: nil, servings: servings.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : servings.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @MainActor private func save() {
        let id = "magazine:\(UUID().uuidString.lowercased())"
        guard let recipe = makeRecipe(id: id) else { errorMessage = "Add a title, at least one ingredient, and one instruction before saving."; return }
        do {
            let encoded = try JSONEncoder().encode(recipe)
            try modelContext.transaction {
                modelContext.insert(ImportedMagazineRecipe(id: id, recipeData: encoded, capturedAt: capturedAt))
                if let category = categories.sorted(by: { $0.order < $1.order }).first {
                    modelContext.insert(RecipeCategoryAssignment(recipeID: id, categoryID: category.id))
                }
            }
            isSaving = true
            savedRecipe = recipe
        } catch { errorMessage = "Could not save the recipe: \(error.localizedDescription)" }
    }
}

struct MagazineRecipeImportHistoryView: View {
    @Query(sort: \ImportedMagazineRecipe.capturedAt, order: .reverse) private var records: [ImportedMagazineRecipe]

    private var activeRecords: [ImportedMagazineRecipe] { records.filter { $0.deletedAt == nil && $0.recipe != nil } }

    var body: some View {
        List(activeRecords, id: \.id) { record in
            if let recipe = record.recipe {
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.title)
                        Text("Magazine photo · \(record.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Magazine photo imports")
    }
}
