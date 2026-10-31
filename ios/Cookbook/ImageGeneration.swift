import Foundation
import SwiftUI
import SwiftData
import UIKit
import ImagePlayground

enum RecipeImageGenerationError: LocalizedError {
    case missingKey
    case invalidResponse
    case api(Int, String)
    case invalidImage
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your OpenAI API key in Settings to generate recipe images."
        case .invalidResponse: "The image service returned an invalid response. Try again."
        case .api(let code, let message): "OpenAI image generation failed (HTTP \(code)): \(message)"
        case .invalidImage: "The generated image could not be opened or saved. Try again."
        case .unavailable(let message): message
        }
    }
}

enum RecipeImageGenerator {
    static let instruction = "Create a realistic editorial cookbook photograph of the finished dish described in the recipe context. Treat the recipe title and complete recipe text as the source of truth; use its ingredients and preparation to determine what the finished dish looks like. Frame it as an appetizing close three-quarter view in a wide 4:3 composition, with natural light and enough detail to read well as a small mobile cookbook tile. Show the prepared dish, not raw ingredients. Do not add major ingredients that conflict with the recipe. No text, lettering, labels, logos, or watermark."

    static func context(for recipe: Recipe) -> String {
        let ingredients = recipe.ingredients.map { "- \($0.quantity.isEmpty ? "" : "\($0.quantity) ")\($0.name)" }.joined(separator: "\n")
        let steps = recipe.steps.map { $0.sectionTitle.isEmpty ? $0.originalInstruction : "\($0.sectionTitle): \($0.originalInstruction)" }.joined(separator: "\n")
        return "# \(recipe.title)\n\n\(recipe.introduction)\n\nIngredients:\n\(ingredients)\n\nInstructions:\n\(steps)\n\nTips:\n\(recipe.tips.joined(separator: "\n"))\n\nHealthier options:\n\(recipe.healthierOptions.joined(separator: "\n"))"
    }

    static func prompt(for recipe: Recipe) -> String { "\(instruction)\n\nRecipe context (complete source text):\n\(context(for: recipe))" }

    static func openAI(recipe: Recipe, key: String, model: String) async throws -> Data {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeImageGenerationError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt(for: recipe), "size": "1536x1152", "quality": "medium", "output_format": "jpeg", "output_compression": 82, "n": 1])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecipeImageGenerationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (root?["error"] as? [String: Any])?["message"] as? String ?? "Check the key, model, quota, and network connection."
            throw RecipeImageGenerationError.api(http.statusCode, message)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (root["data"] as? [[String: Any]])?.first,
              let encoded = first["b64_json"] as? String,
              let image = Data(base64Encoded: encoded), UIImage(data: image) != nil else { throw RecipeImageGenerationError.invalidResponse }
        return image
    }

    @MainActor static func save(_ data: Data, recipeID: String, photos: [RecipePhoto], context: ModelContext) throws -> RecipePhoto {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.86) else { throw RecipeImageGenerationError.invalidImage }
        let name = "GeneratedRecipeImages/\(UUID().uuidString).jpg"
        let url = UserFiles.url(for: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url, options: .atomic)
        let photo = RecipePhoto(recipeID: recipeID, relativePath: name, isCover: true)
        photos.filter { $0.recipeID == recipeID }.forEach { $0.isCover = false }
        context.insert(photo)
        try context.save()
        return photo
    }

    @MainActor static func restore(_ entry: ImageGenerationEntry, photos: [RecipePhoto], context: ModelContext) throws -> Bool {
        guard let generatedID = entry.generatedPhotoID,
              let generated = photos.first(where: { $0.id.uuidString == generatedID && $0.recipeID == entry.recipeID && $0.isCover }) else { return false }
        generated.isCover = false
        if let previousID = entry.previousPhotoID,
           let previous = photos.first(where: { $0.id.uuidString == previousID && $0.recipeID == entry.recipeID }) {
            previous.isCover = true
        }
        try context.save()
        entry.status = "restored"
        try context.save()
        return true
    }
}

struct RecipeImageGenerationView: View {
    let recipes: [Recipe]
    var resumeRun: ImageGenerationRun?
    var bulkOperation = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [RecipePhoto]
    @Query private var entries: [ImageGenerationEntry]
    @AppStorage("imageAIProvider") private var provider = "openai"
    @AppStorage("imageOpenAIModel") private var model = "gpt-image-2.5-flare"
    @State private var activeRun: ImageGenerationRun?
    @State private var currentEntryID: UUID?
    @State private var currentRecipeID: String?
    @State private var presentingPlayground = false
    @State private var isProcessing = false
    @State private var stopAfterCurrent = false
    @State private var status: String?
    @State private var resultMessage: String?

    private var recipeByID: [String: Recipe] { Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) }) }
    private var history: [ImageGenerationEntry] { entries.filter { $0.recipeID == recipes.first?.id }.sorted { $0.id.uuidString > $1.id.uuidString } }
    private var generatedEntries: [ImageGenerationEntry] {
        guard let runID = activeRun?.id else { return [] }
        return entries.filter { $0.runID == runID && $0.generatedPhotoID != nil }
    }
    private var showsBulkResults: Bool { bulkOperation && !isProcessing && resultMessage != nil }
    private var currentRecipe: Recipe? { currentRecipeID.flatMap { recipeByID[$0] } }
    @available(iOS 18.1, *)
    private var playgroundConcepts: [ImagePlaygroundConcept] {
        guard let recipe = currentRecipe else { return [] }
        return [
            .text("The finished, ready-to-eat \(recipe.title), plated as an appetizing cookbook dish. Show the prepared dish, not separate raw ingredients."),
            .extracted(from: RecipeImageGenerator.context(for: recipe), title: recipe.title)
        ]
    }
    private var shouldAttachPlaygroundPresenter: Bool {
        provider == "on-device" || resumeRun?.provider == "on-device" || activeRun?.provider == "on-device"
    }

    @ViewBuilder
    var body: some View {
        if presentingPlayground && shouldAttachPlaygroundPresenter {
            if #available(iOS 18.1, *) {
                generationContent.modifier(RecipeImagePlaygroundPresenter(isPresented: $presentingPlayground, concepts: playgroundConcepts, completion: { url in
                    do { try accept(try Data(contentsOf: url)) }
                    catch { failCurrent(error.localizedDescription) }
                }, cancellation: { failCurrent("Generation was cancelled. You can resume this run later.") }))
            } else {
                generationContent
            }
        } else {
            if showsBulkResults { bulkResultsContent }
            else { generationContent }
        }
    }

    private var bulkResultsContent: some View {
        List {
            Section {
                Label(generatedEntries.isEmpty ? "No covers generated" : "Covers ready to review", systemImage: generatedEntries.isEmpty ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .font(.headline)
                Text(resultMessage ?? "").font(.footnote).foregroundStyle(.secondary)
            }
            if !generatedEntries.isEmpty {
                Section("Generated covers · \(generatedEntries.count)") {
                    ForEach(generatedEntries) { entry in
                        if let recipe = recipeByID[entry.recipeID] {
                            NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                                HStack(spacing: 12) {
                                    if let photo = generatedPhoto(for: entry),
                                       let image = UIImage(contentsOfFile: UserFiles.url(for: photo.relativePath).path) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 76, height: 64).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
                                    }
                                    Text(recipe.title).font(.body.weight(.medium))
                                }
                            }
                        }
                    }
                    if let runID = activeRun?.id {
                        NavigationLink {
                            RecipeBrowserView(managesNavigationStack: false, screenTitle: "Generated recipes", imageRunID: runID)
                        } label: {
                            Label("View generated recipes", systemImage: "square.grid.2x2")
                        }
                    }
                }
            }
            Section {
                Button("Done") { dismiss() }
            }
        }
        .navigationTitle("Review generated covers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generatedPhoto(for entry: ImageGenerationEntry) -> RecipePhoto? {
        guard let photoID = entry.generatedPhotoID else { return nil }
        return photos.first { $0.id.uuidString == photoID }
    }

    private var generationContent: some View {
        List {
            Section("Image generation") {
                Text(recipes.count == 1 ? recipes[0].title : "\(recipes.count) recipes")
                Button { begin() } label: {
                    Label(isProcessing ? "Generating…" : recipes.count == 1 ? (hasImage ? "Regenerate cover" : "Generate cover") : "Generate images without covers", systemImage: "sparkles")
                }.disabled(isProcessing || recipes.isEmpty)
                if isProcessing { ProgressView("Saving each result as it completes") }
                if isProcessing { Button("Stop after this image") { stopAfterCurrent = true }.foregroundStyle(.secondary) }
                if let resultMessage { Text(resultMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            if recipes.count == 1 {
                Section("Image history") {
                    let recipeID = recipes[0].id
                    let versions = photos.filter { $0.recipeID == recipeID }.sorted { $0.createdAt > $1.createdAt }
                    if versions.isEmpty { Text("No saved image versions yet.").foregroundStyle(.secondary) }
                    ForEach(versions) { photo in
                        HStack {
                            if let image = UIImage(contentsOfFile: UserFiles.url(for: photo.relativePath).path) { Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 7)) }
                            VStack(alignment: .leading) { Text(photo.isCover ? "Current cover" : "Saved image"); Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if !photo.isCover { Button("Restore") { restore(photo) }.buttonStyle(.bordered) }
                        }
                    }
                    if recipeByID[recipeID]?.thumbnailAsset != nil {
                        Button("Restore bundled cover") { restoreBundled() }
                    } else if photos.contains(where: { $0.recipeID == recipeID && $0.isCover }) {
                        Button("Return to no cover", role: .destructive) { restoreBundled() }
                    }
                }
            }
        }
        .navigationTitle(recipes.count == 1 ? "Recipe images" : "Generate images")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Recipe images", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) { Button("OK") { status = nil } } message: { Text(status ?? "") }
        .task { if let resumeRun { start(resumeRun) } }
    }

    private var hasImage: Bool {
        guard let recipe = recipes.first else { return false }
        return photos.contains(where: { $0.recipeID == recipe.id && $0.isCover }) || bundledImageExists(recipe)
    }

    private func bundledImageExists(_ recipe: Recipe) -> Bool {
        guard let name = recipe.thumbnailAsset else { return false }
        return Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Thumbnails") != nil
    }

    @MainActor private func begin() {
        guard provider != "openai" || !KeychainKey.read().isEmpty else { status = RecipeImageGenerationError.missingKey.localizedDescription; return }
        let id = UUID()
        let run = ImageGenerationRun(id: id, provider: provider, model: provider == "openai" ? model : "Image Playground", isBulk: bulkOperation, recipeCount: recipes.count)
        context.insert(run)
        for recipe in recipes {
            let previous = photos.first(where: { $0.recipeID == recipe.id && $0.isCover })
            let bundle = previous == nil && bundledImageExists(recipe) ? recipe.thumbnailAsset : nil
            context.insert(ImageGenerationEntry(runID: id, recipeID: recipe.id, previousPhotoID: previous?.id.uuidString, previousBundledAsset: bundle, previousHadNoImage: previous == nil && bundle == nil))
        }
        do { try context.save(); start(run) } catch { status = "Could not start image generation: \(error.localizedDescription)" }
    }

    @MainActor private func start(_ run: ImageGenerationRun) {
        activeRun = run
        let runID = run.id
        let descriptor = FetchDescriptor<ImageGenerationEntry>(predicate: #Predicate { $0.runID == runID && ($0.status == "failed" || $0.status == "generating") })
        for entry in (try? context.fetch(descriptor)) ?? [] {
            if entry.status == "failed" { run.failedCount = max(0, run.failedCount - 1) }
            entry.status = "pending"; entry.errorMessage = nil
        }
        run.status = "running"
        try? context.save()
        isProcessing = true
        processNext()
    }

    @MainActor private func processNext() {
        guard let run = activeRun else { return }
        if stopAfterCurrent {
            stopAfterCurrent = false; run.status = "interrupted"; try? context.save(); isProcessing = false
            resultMessage = "Run paused. Completed images are saved; resume it from Settings."
            return
        }
        let runID = run.id
        let descriptor = FetchDescriptor<ImageGenerationEntry>(predicate: #Predicate { $0.runID == runID && $0.status == "pending" })
        guard let next = (try? context.fetch(descriptor))?.first else {
            let entriesDescriptor = FetchDescriptor<ImageGenerationEntry>(predicate: #Predicate { $0.runID == runID })
            let runEntries = (try? context.fetch(entriesDescriptor)) ?? []
            let skippedCount = runEntries.filter { $0.status == "skipped" }.count
            run.status = run.failedCount > 0 ? "completed with errors" : skippedCount > 0 ? "completed with skips" : "completed"
            try? context.save(); isProcessing = false
            resultMessage = "Generated \(run.completedCount) of \(run.recipeCount) covers.\(run.failedCount > 0 ? " \(run.failedCount) need retry." : "")\(skippedCount > 0 ? " \(skippedCount) were skipped because a cover was added later." : "")"
            return
        }
        if run.isBulk && next.previousPhotoID == nil && photos.contains(where: { $0.recipeID == next.recipeID && $0.isCover }) {
            next.status = "skipped"; next.errorMessage = "A cover was added after this run started."
            try? context.save()
            Task { @MainActor in processNext() }
            return
        }
        currentEntryID = next.id
        currentRecipeID = next.recipeID
        next.status = "generating"
        try? context.save()
        guard let recipe = recipeByID[next.recipeID] else { failCurrent("Recipe is no longer available."); return }
        if run.provider == "on-device" {
            guard #available(iOS 18.1, *) else { failCurrent("On-device image generation requires iOS 18.1 or later."); return }
            presentingPlayground = true
        } else {
            Task {
                do { try accept(try await RecipeImageGenerator.openAI(recipe: recipe, key: KeychainKey.read(), model: run.model)) }
                catch { failCurrent(error.localizedDescription) }
            }
        }
    }

    @MainActor private func accept(_ data: Data) throws {
        guard let run = activeRun, let id = currentEntryID else { throw RecipeImageGenerationError.invalidResponse }
        let entry = entries.first(where: { $0.id == id }) ?? (try? context.fetch(FetchDescriptor<ImageGenerationEntry>(predicate: #Predicate { $0.id == id })))?.first
        guard let entry else { throw RecipeImageGenerationError.invalidResponse }
        let photo = try RecipeImageGenerator.save(data, recipeID: entry.recipeID, photos: photos, context: context)
        entry.generatedPhotoID = photo.id.uuidString; entry.status = "completed"; entry.errorMessage = nil
        run.completedCount += 1
        try context.save()
        currentEntryID = nil
        currentRecipeID = nil
        processNext()
    }

    @MainActor private func failCurrent(_ message: String) {
        guard let run = activeRun, let id = currentEntryID, let entry = entries.first(where: { $0.id == id }) else { isProcessing = false; status = message; return }
        entry.status = "failed"; entry.errorMessage = message
        run.failedCount += 1
        try? context.save()
        currentEntryID = nil
        currentRecipeID = nil
        if provider == "on-device" && message.contains("cancel") { run.status = "interrupted"; isProcessing = false; try? context.save(); resultMessage = message }
        else { processNext() }
    }

    @MainActor private func restore(_ photo: RecipePhoto) {
        guard let recipeID = recipes.first?.id else { return }
        photos.filter { $0.recipeID == recipeID }.forEach { $0.isCover = ($0.id == photo.id) }
        do { try context.save() } catch { status = "Could not restore image: \(error.localizedDescription)" }
    }

    @MainActor private func restoreBundled() {
        guard let recipeID = recipes.first?.id else { return }
        photos.filter { $0.recipeID == recipeID }.forEach { $0.isCover = false }
        do { try context.save() } catch { status = "Could not restore the bundled cover: \(error.localizedDescription)" }
    }
}

struct ImageGenerationSettingsView: View {
    @AppStorage("imageAIProvider") private var provider = "openai"
    @AppStorage("imageOpenAIModel") private var model = "gpt-image-2.5-flare"
    @Query private var imported: [ImportedPaprikaRecipe]
    @Query private var deleted: [DeletedRecipe]
    @Query private var photos: [RecipePhoto]
    @Query(sort: \ImageGenerationRun.createdAt, order: .reverse) private var runs: [ImageGenerationRun]

    private var recipes: [Recipe] {
        let deletedIDs = Set(deleted.map(\.recipeID))
        return CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + imported.filter { $0.deletedAt == nil }.compactMap(\.recipe)
    }
    private var eligible: [Recipe] { recipes.filter { recipe in
        !photos.contains(where: { $0.recipeID == recipe.id && $0.isCover }) && recipe.thumbnailAsset.flatMap { Bundle.main.url(forResource: $0, withExtension: nil, subdirectory: "Thumbnails") } == nil
    } }

    var body: some View {
        List {
            Section("Provider") {
                Picker("Image provider", selection: $provider) { Text("OpenAI (cloud)").tag("openai"); Text("On-device Image Playground").tag("on-device") }
                if provider == "openai" {
                    Picker("Image model", selection: $model) {
                        Text("GPT Image 2.5 Flare").tag("gpt-image-2.5-flare")
                        Text("GPT Image 2.5 Sunburst").tag("gpt-image-2.5-sunburst")
                    }
                    Text("Uses the shared OpenAI API key from Keychain. OpenAI cloud generation makes a direct request using the selected image model.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Uses Apple's system Image Playground sheet and system-managed image model. Each recipe needs an interaction and may be cancelled; completed images are saved immediately. Requires iOS 18.1 or later and supported device capabilities.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Missing covers") {
                NavigationLink { RecipeImageGenerationView(recipes: eligible, resumeRun: nil, bulkOperation: true) } label: {
                    Label("Generate images for recipes without covers (\(eligible.count))", systemImage: "sparkles")
                }.disabled(eligible.isEmpty)
                if eligible.isEmpty { Text("Every active recipe already has a saved or bundled cover.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Previous runs") {
                if runs.isEmpty { Text("Bulk image runs will appear here.").foregroundStyle(.secondary) }
                ForEach(runs) { run in NavigationLink {
                    ImageGenerationRunDetailView(run: run, recipes: recipes)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                        Text("\(run.completedCount)/\(run.recipeCount) images · \(run.status) · \(run.provider == "openai" ? run.model : "On-device")").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                } }
            }
        }
        .navigationTitle("Recipe images")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ImageGenerationRunDetailView: View {
    let run: ImageGenerationRun
    let recipes: [Recipe]
    @Environment(\.modelContext) private var context
    @Query private var entries: [ImageGenerationEntry]
    @Query private var photos: [RecipePhoto]
    @State private var message: String?

    private var runEntries: [ImageGenerationEntry] { entries.filter { $0.runID == run.id } }
    private var generatedRecipes: [Recipe] { let ids = Set(runEntries.filter { $0.generatedPhotoID != nil }.map(\.recipeID)); return recipes.filter { ids.contains($0.id) } }

    var body: some View {
        List {
            Section {
                NavigationLink { RecipeBrowserView(managesNavigationStack: false, screenTitle: "Generated recipes", imageRunID: run.id) } label: { Label("Review \(generatedRecipes.count) recipes", systemImage: "square.grid.2x2") }
                NavigationLink { RecipeImageGenerationView(recipes: recipes, resumeRun: run, bulkOperation: run.isBulk) } label: { Label("Resume unfinished images", systemImage: "arrow.clockwise") }
                    .disabled(!runEntries.contains(where: { $0.status == "pending" || $0.status == "failed" || $0.status == "generating" }))
                Button("Undo all unchanged covers", role: .destructive) { undoAll() }
                    .disabled(!runEntries.contains(where: { $0.generatedPhotoID != nil && $0.status != "restored" }))
            }
            Section("Run results") {
                ForEach(runEntries) { entry in
                    HStack { Text(recipes.first(where: { $0.id == entry.recipeID })?.title ?? entry.recipeID); Spacer(); Text(entry.status).font(.caption).foregroundStyle(.secondary) }
                    if let error = entry.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Image run")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Image generation", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }

    @MainActor private func undoAll() {
        var restored = 0; var skipped = 0
        for entry in runEntries where entry.generatedPhotoID != nil && entry.status != "restored" {
            do { if try RecipeImageGenerator.restore(entry, photos: photos, context: context) { restored += 1 } else { skipped += 1 } }
            catch { skipped += 1 }
        }
        message = "Restored \(restored) covers. Skipped \(skipped) because the current cover changed or could not be restored."
        run.status = "undone"; try? context.save()
    }
}

@available(iOS 18.1, *)
private struct RecipeImagePlaygroundPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let concepts: [ImagePlaygroundConcept]
    let completion: (URL) -> Void
    let cancellation: () -> Void
    func body(content: Content) -> some View {
        content.imagePlaygroundSheet(isPresented: $isPresented, concepts: concepts, sourceImage: nil, onCompletion: completion, onCancellation: cancellation)
    }
}
