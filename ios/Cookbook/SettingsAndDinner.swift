import SwiftUI
import SwiftData
import EventKit
import Security
import UIKit

struct SettingsView: View {
    @Binding var incomingPaprikaURL: URL?
    @AppStorage("reminderListID") private var reminderListID = ""
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openAIModel") private var openAIModel = "gpt-6-astra"
    @State private var reminderListName = "Not selected"
    @State private var reminderLists: [ReminderListChoice] = []
    @State private var status: String?
    @State private var exportURL: URL?
    @State private var markdownRecipeExportURL: URL?
    @State private var htmlRecipeExportURL: URL?
    @State private var exportingRecipeDocuments = false
    @State private var paprikaExportURL: URL?
    @State private var exportingPaprika = false
    @State private var showingPaprikaExportSelector = false
    @State private var markdownURL: URL?
    @State private var showingPaprikaImporter = false
    @State private var importReview: PaprikaImportReviewSession?
    @State private var webCapture: PaprikaShareInbox.WebCapture?
    @State private var webCapturePendingURL: URL?
    @State private var processingShareURL: URL?
    @Query(sort: \RecipeNote.updatedAt, order: .reverse) private var notes: [RecipeNote]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query(sort: \ImportedWebRecipe.capturedAt, order: .reverse) private var importedWebRecords: [ImportedWebRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @Query(sort: \PaprikaImportRun.createdAt, order: .reverse) private var paprikaImportRuns: [PaprikaImportRun]
    @Query private var recipePhotos: [RecipePhoto]
    private let reminderStore = EKEventStore()

    private var activeRecipeCount: Int {
        let bundledCount = CookbookCatalog.bundled.recipes.count - deletedRecipes.count
        let paprikaCount = importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe).count
        let webCaptureCount = importedWebRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe).count
        return bundledCount + paprikaCount + webCaptureCount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    SettingsGroupLabel(title: "Categories")
                    NavigationLink {
                        RecipeCategoryManagerView()
                    } label: {
                        Label("Manage categories", systemImage: "folder")
                    }
                    Text("Choose the Recipes list sections and the default category for unmatched imports.").font(.footnote).foregroundStyle(.secondary)
                    SettingsGroupLabel(title: "Recipe notes")
                    Text("\(notes.filter { $0.deletedAt == nil }.count) saved notes")
                    Button("Export notes with timestamps") { exportNotes() }
                    if let exportURL { ShareLink(item: exportURL) { Label("Share JSON export", systemImage: "square.and.arrow.up") } }
                    if let markdownURL { ShareLink(item: markdownURL) { Label("Share Markdown companion", systemImage: "doc.text") } }
                    Text("Exports preserve each note's original text, recipe ID, optional step ID, and creation/update timestamps.").font(.footnote).foregroundStyle(.secondary)
                    SettingsGroupLabel(title: "Recipe activity")
                    NavigationLink {
                        RecipeUsageStatsView()
                    } label: {
                        Label("Recipe popularity counts", systemImage: "chart.bar")
                    }
                    Text("Counts are stored on this device only. They are a local usage signal, not cross-user popularity data.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Cooking") {
                    SettingsGroupLabel(title: "Grocery list")
                    if reminderLists.isEmpty { LabeledContent("Reminders list", value: reminderListName) }
                    else { Picker("Reminders list", selection: $reminderListID) {
                        Text("Select a list").tag("")
                        ForEach(reminderLists) { Text($0.title).tag($0.id) }
                    }.onChange(of: reminderListID) { _, id in
                        if let choice = reminderLists.first(where: { $0.id == id }) { reminderListName = choice.title; UserDefaults.standard.set(choice.title, forKey: "reminderListName") }
                    } }
                    Button("Load Reminders lists") { Task { await loadReminderLists() } }
                    Text("Cookbook checks the selected list for duplicate incomplete items before adding quantity-free ingredients.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Import & export") {
                    SettingsGroupLabel(title: "Capture from Safari")
                    Label("Capture a recipe in Safari", systemImage: "safari")
                    Text("In Safari, tap Share and choose Cookbook. The page is captured automatically. iOS returns you to Safari after the share extension finishes; open Cookbook to review and save it.").font(.footnote).foregroundStyle(.secondary)
                    Text("Page text is extracted with your configured OpenAI model. Cookbook also tries the photo URL supplied by Safari, using a normal image request.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(importedWebRecords.filter { $0.deletedAt == nil }.prefix(3), id: \.id) { record in
                        if let recipe = record.recipe {
                            NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recipe.title)
                                    Text("\(recipe.provenance?.tagLabel ?? "Safari") · \(record.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if importedWebRecords.contains(where: { $0.deletedAt == nil }) {
                        NavigationLink("All Safari captures (\(importedWebRecords.filter { $0.deletedAt == nil }.count))") {
                            SafariRecipeImportHistoryView(records: importedWebRecords.filter { $0.deletedAt == nil })
                        }
                    }
                    SettingsGroupLabel(title: "Paprika files")
                    Button { showingPaprikaImporter = true } label: { Label("Import Paprika recipes…", systemImage: "square.and.arrow.down") }
                    Text("Review recipes before adding them. Paprika imports stay on this device and are marked internally.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(paprikaImportRuns.prefix(3), id: \.id) { run in PaprikaImportRunRow(run: run) }
                    if paprikaImportRuns.count > 3 {
                        NavigationLink("All Paprika import runs (\(paprikaImportRuns.count))") { PaprikaImportHistoryView() }
                    }
                    NavigationLink {
                        RecipeBrowserView(showingDeletedRecipes: true, managesNavigationStack: false, screenTitle: "Deleted recipes")
                    } label: {
                        Label("Deleted recipes (\(importedRecords.filter { $0.deletedAt != nil }.count + importedWebRecords.filter { $0.deletedAt != nil }.count + deletedRecipes.count))", systemImage: "trash")
                    }
                    SettingsGroupLabel(title: "Export recipes")
                    Button { showingPaprikaExportSelector = true } label: {
                        Label(exportingPaprika ? "Preparing export…" : "Choose recipes to export…", systemImage: "square.and.arrow.up")
                    }.disabled(exportingPaprika)
                    if let paprikaExportURL {
                        ShareLink(item: paprikaExportURL) { Label("Share Paprika collection", systemImage: "square.and.arrow.up") }
                    }
                    Text("Exports all active bundled and imported recipes, regardless of browse filters.").font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { await exportRecipeCollection(format: .markdown) }
                    } label: {
                        Label(exportingRecipeDocuments ? "Preparing export…" : "Export all recipes as Markdown…", systemImage: "doc.zipper")
                    }.disabled(exportingRecipeDocuments)
                    if let markdownRecipeExportURL {
                        ShareLink(item: markdownRecipeExportURL) { Label("Share Markdown archive", systemImage: "square.and.arrow.up") }
                    }
                    Button {
                        Task { await exportRecipeCollection(format: .html) }
                    } label: {
                        Label(exportingRecipeDocuments ? "Preparing export…" : "Export all recipes as HTML…", systemImage: "chevron.left.forwardslash.chevron.right")
                    }.disabled(exportingRecipeDocuments)
                    if let htmlRecipeExportURL {
                        ShareLink(item: htmlRecipeExportURL) { Label("Share HTML cookbook", systemImage: "square.and.arrow.up") }
                    }
                    Text("Exports every active bundled and imported recipe, regardless of browse filters. Markdown is a ZIP archive with one recipe per file; HTML is a standalone cookbook.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("AI & images") {
                    OpenAIKeySettingsSection()
                    SettingsGroupLabel(title: "Recipe images")
                    NavigationLink {
                        ImageGenerationSettingsView()
                    } label: {
                        Label("Generate missing recipe covers", systemImage: "sparkles")
                    }
                    Text("Choose an image provider and review or undo previous batch runs.").font(.footnote).foregroundStyle(.secondary)
                    SettingsGroupLabel(title: "Dinner planning")
                    Picker("AI provider", selection: $aiProvider) { Text("OpenAI (cloud)").tag("openai"); Text("On-device").tag("on-device") }
                    if aiProvider == "openai" {
                        TextField("Model", text: $openAIModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        Text("Requires iOS 26 or later, an Apple Intelligence-capable iPhone, Apple Intelligence enabled, a supported language and region, and the on-device model ready. The plan is generated on this iPhone; there is no cloud fallback.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Provider choice is explicit. The on-device option never falls back to the cloud.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") { LabeledContent("Recipe catalog", value: "\(activeRecipeCount) recipes · offline") }
            }
            .navigationTitle("Settings")
            .onAppear {
                reminderListName = UserDefaults.standard.string(forKey: "reminderListName") ?? "Not selected"
                if let incomingPaprikaURL {
                    processIncomingShare(incomingPaprikaURL)
                } else if let pendingURL = PaprikaShareInbox.nextPendingURL() {
                    processIncomingShare(pendingURL)
                }
            }
            .fileImporter(isPresented: $showingPaprikaImporter, allowedContentTypes: PaprikaFileType.supported, allowsMultipleSelection: false, onCompletion: handlePaprikaSelection)
            .sheet(item: $importReview, onDismiss: openNextPendingPaprikaShare) { session in PaprikaImportReviewView(session: session) }
            .sheet(isPresented: Binding(get: { webCapture != nil }, set: { if !$0 { webCapture = nil } }), onDismiss: {
                if let webCapturePendingURL { PaprikaShareInbox.removeIfPending(webCapturePendingURL) }
                webCapturePendingURL = nil
                processingShareURL = nil
                openNextPendingPaprikaShare()
            }) {
                if let webCapture { WebRecipeImportReviewView(capture: webCapture, model: openAIModel) }
            }
            .sheet(isPresented: $showingPaprikaExportSelector) {
                NavigationStack {
                    PaprikaExportSelectorView(
                        recipes: activePaprikaRecipes,
                        groups: paprikaLabelGroups,
                        labels: paprikaLabels,
                        sourceChoices: paprikaExportSources,
                        collectionChoices: paprikaExportCollections
                    ) { selectedLabelIDs, selectedSourceIDs, selectedCollectionIDs in
                        showingPaprikaExportSelector = false
                        Task {
                            await exportPaprikaRecipes(
                                selectedLabelIDs: selectedLabelIDs,
                                selectedSourceIDs: selectedSourceIDs,
                                selectedCollectionIDs: selectedCollectionIDs
                            )
                        }
                    }
                }
            }
            .onChange(of: incomingPaprikaURL) { _, url in
                guard let url else { return }
                processIncomingShare(url)
            }
            .alert("Cookbook", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) { Button("OK") { status = nil } } message: { Text(status ?? "") }
        }
    }

    private func handlePaprikaSelection(_ result: Result<[URL], Error>) {
        do {
            let urls: [URL]
            do { urls = try result.get() } catch is CancellationError { return }
            guard let url = urls.first else { return }
            importPaprikaFile(url)
        } catch { status = "Could not open the selected file: \(error.localizedDescription)" }
    }

    private func importPaprikaFile(_ url: URL) {
        if url.pathExtension == "webrecipecapture" {
            do {
                webCapture = try PaprikaShareInbox.readWebCapture(at: url)
                webCapturePendingURL = url
            } catch {
                PaprikaShareInbox.removeIfPending(url)
                processingShareURL = nil
                status = error.localizedDescription
            }
            return
        }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            Task {
                do {
                    let drafts = try await Task.detached(priority: .userInitiated) { try PaprikaImportReader.parse(data: data) }.value
                    PaprikaShareInbox.removeIfPending(url)
                    processingShareURL = nil
                    guard !drafts.isEmpty else { status = "This Paprika file contains no importable recipes."; return }
                    importReview = PaprikaImportReviewSession(drafts: drafts)
                } catch is CancellationError { processingShareURL = nil; return }
                catch {
                    PaprikaShareInbox.removeIfPending(url)
                    processingShareURL = nil
                    status = error.localizedDescription
                }
            }
        } catch {
            processingShareURL = nil
            status = "Could not open the selected file: \(error.localizedDescription)"
        }
    }

    private func processIncomingShare(_ url: URL) {
        incomingPaprikaURL = nil
        guard processingShareURL != url else { return }
        processingShareURL = url
        importPaprikaFile(url)
    }

    private func openNextPendingPaprikaShare() {
        guard incomingPaprikaURL == nil, processingShareURL == nil,
              let nextURL = PaprikaShareInbox.nextPendingURL() else { return }
        incomingPaprikaURL = nextURL
    }

    @MainActor private func loadReminderLists() async {
        do {
            if #available(iOS 17.0, *) { try await reminderStore.requestFullAccessToReminders() } else { try await reminderStore.requestAccess(to: .reminder) }
            reminderLists = reminderStore.calendars(for: .reminder).filter(\.allowsContentModifications).map { ReminderListChoice(id: $0.calendarIdentifier, title: $0.title) }
            guard !reminderLists.isEmpty else { status = "No writable Reminders lists are available."; return }
            if !reminderLists.contains(where: { $0.id == reminderListID }) {
                reminderListName = reminderListID.isEmpty ? "Choose a list" : "Unavailable — choose another"
                if !reminderListID.isEmpty { status = "The previously selected Reminders list is unavailable. Choose a replacement explicitly." }
            }
        } catch { status = "Reminders access is unavailable. You can allow it in iPhone Settings." }
    }

    private func exportNotes() {
        struct NoteExport: Codable { let id: UUID; let recipeID: String; let stepID: String?; let text: String; let createdAt: String; let updatedAt: String; let catalogHash: String }
        let formatter = ISO8601DateFormatter()
        let records = notes.filter { $0.deletedAt == nil }.map { NoteExport(id: $0.id, recipeID: $0.recipeID, stepID: $0.stepID, text: $0.text, createdAt: formatter.string(from: $0.createdAt), updatedAt: formatter.string(from: $0.updatedAt), catalogHash: $0.catalogHash) }
        let stamp = Int(Date().timeIntervalSince1970)
        let path = UserFiles.directory.appendingPathComponent("recipe-notes-\(stamp).json")
        let markdownPath = UserFiles.directory.appendingPathComponent("recipe-notes-\(stamp).md")
        let json = (try? JSONEncoder.pretty.encode(records)) ?? Data("[]".utf8)
        let allRecipes = CookbookCatalog.bundled.recipes + importedRecords.compactMap(\.recipe) + importedWebRecords.compactMap(\.recipe)
        let titles = Dictionary(uniqueKeysWithValues: allRecipes.map { ($0.id, $0.title) })
        let body = records.map { record in
            "## \(titles[record.recipeID] ?? record.recipeID)\n\n- Note ID: `\(record.id.uuidString)`\n- Recipe ID: `\(record.recipeID)`\n- Step ID: \(record.stepID ?? "whole recipe")\n- Created: \(record.createdAt)\n- Updated: \(record.updatedAt)\n\n\(record.text)"
        }.joined(separator: "\n\n---\n\n")
        do { try json.write(to: path, options: .atomic); try Data(("# Cookbook notes\n\n" + body + "\n").utf8).write(to: markdownPath, options: .atomic); exportURL = path; self.markdownURL = markdownPath } catch { status = "Could not export notes: \(error.localizedDescription)" }
    }

    private var activePaprikaRecipes: [Recipe] {
        let deletedIDs = Set(deletedRecipes.map(\.recipeID))
        return CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) }
            + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
            + importedWebRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
    }

    private var paprikaLabelGroups: [RecipeLabelGroup] {
        (CookbookCatalog.bundled.labelGroups ?? []).sorted { $0.order < $1.order }
    }

    private var paprikaLabels: [RecipeLabel] {
        (CookbookCatalog.bundled.labels ?? []).sorted {
            if $0.groupID == $1.groupID { return $0.order < $1.order }
            let groupOrder = Dictionary(uniqueKeysWithValues: paprikaLabelGroups.map { ($0.id, $0.order) })
            return (groupOrder[$0.groupID] ?? .max) < (groupOrder[$1.groupID] ?? .max)
        }
    }

    private var paprikaExportSources: [PaprikaExportFilterChoice] {
        let importedIDs = Set(importedRecords.filter { $0.deletedAt == nil && $0.recipe != nil }.map(\.id))
        var choices: [String: PaprikaExportFilterChoice] = [:]
        func add(_ id: String, title: String, recipeID: String) {
            var choice = choices[id] ?? PaprikaExportFilterChoice(id: id, title: title, recipeIDs: [])
            choice.recipeIDs.insert(recipeID)
            choices[id] = choice
        }

        for recipe in activePaprikaRecipes {
            if importedIDs.contains(recipe.id) { add("paprika-imports", title: "Paprika imports", recipeID: recipe.id) }
            guard let provenance = recipe.provenance else { continue }
            switch provenance.type {
            case .personalCookbook, .cookbookRepository:
                add("personal-cookbook", title: "Personal cookbook", recipeID: recipe.id)
            case .paprikaImport:
                add("paprika-imports", title: "Paprika imports", recipeID: recipe.id)
                if let source = provenanceSourceName(provenance) {
                    add("source:\(RecipeLabel.normalize(source))", title: source, recipeID: recipe.id)
                }
            case .website, .manual, .other:
                if let source = provenanceSourceName(provenance) {
                    add("source:\(RecipeLabel.normalize(source))", title: source, recipeID: recipe.id)
                }
            }
        }

        let priority = ["personal-cookbook": 0, "paprika-imports": 1]
        return choices.values.sorted {
            let left = priority[$0.id] ?? 2
            let right = priority[$1.id] ?? 2
            if left != right { return left < right }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func provenanceSourceName(_ provenance: RecipeProvenance) -> String? {
        let source = provenance.tagLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              RecipeLabel.normalize(source) != RecipeLabel.normalize("Paprika"),
              RecipeLabel.normalize(source) != RecipeLabel.normalize("Personal cookbook"),
              RecipeLabel.normalize(source) != RecipeLabel.normalize("Paprika imports") else { return nil }
        return source
    }

    private var paprikaExportCollections: [PaprikaExportFilterChoice] {
        var recipeIDsByCollection: [String: Set<String>] = [:]
        var titleByCollection: [String: String] = [:]
        for recipe in activePaprikaRecipes {
            guard let title = recipe.collectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
            let id = RecipeLabel.normalize(title)
            titleByCollection[id] = title
            recipeIDsByCollection[id, default: []].insert(recipe.id)
        }
        return recipeIDsByCollection.map { id, recipeIDs in
            PaprikaExportFilterChoice(id: "collection:\(id)", title: titleByCollection[id] ?? id, recipeIDs: recipeIDs)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @MainActor private func exportPaprikaRecipes(selectedLabelIDs: Set<String>, selectedSourceIDs: Set<String>, selectedCollectionIDs: Set<String>) async {
        exportingPaprika = true
        defer { exportingPaprika = false }
        do {
            let recipes = activePaprikaRecipes.filter { recipe in
                let matchesSource = selectedSourceIDs.isEmpty || paprikaExportSources.contains { selectedSourceIDs.contains($0.id) && $0.recipeIDs.contains(recipe.id) }
                let matchesCollection = selectedCollectionIDs.isEmpty || paprikaExportCollections.contains { selectedCollectionIDs.contains($0.id) && $0.recipeIDs.contains(recipe.id) }
                let matchesLabels = selectedLabelIDs.isEmpty || RecipeLabelFilter.matches(recipe, selectedLabelIDs: selectedLabelIDs, groups: paprikaLabelGroups, labels: paprikaLabels)
                return matchesSource && matchesCollection && matchesLabels
            }
            guard !recipes.isEmpty else { throw PaprikaExportError.noRecipes }
            let items = try recipes.map { try PaprikaExporter.item(for: $0, importedRecords: importedRecords, photos: recipePhotos) }
            let url = PaprikaExporter.temporaryURL(extension: "paprikarecipes")
            try await Task.detached(priority: .userInitiated) { try PaprikaExporter.writeCollection(items, to: url) }.value
            paprikaExportURL = url
            status = "Prepared a Paprika export with \(items.count) recipes."
        } catch { status = "Could not export Paprika recipes: \(error.localizedDescription)" }
    }

    private enum RecipeCollectionFormat: Equatable, Sendable {
        case markdown
        case html
    }

    @MainActor private func exportRecipeCollection(format: RecipeCollectionFormat) async {
        exportingRecipeDocuments = true
        defer { exportingRecipeDocuments = false }
        switch format {
        case .markdown: markdownRecipeExportURL = nil
        case .html: htmlRecipeExportURL = nil
        }
        do {
            let recipes = activePaprikaRecipes
            guard !recipes.isEmpty else { throw RecipeDocumentExportError.noRecipes }
            let fileExtension = format == .markdown ? "zip" : "html"
            let url = RecipeDocumentExporter.temporaryURL(extension: fileExtension)
            try await Task.detached(priority: .userInitiated) {
                switch format {
                case .markdown: try RecipeDocumentExporter.writeMarkdownArchive(recipes, to: url)
                case .html: try RecipeDocumentExporter.writeHTMLCookbook(recipes, to: url)
                }
            }.value
            switch format {
            case .markdown:
                markdownRecipeExportURL = url
                status = "Prepared a Markdown archive with \(recipes.count) recipes."
            case .html:
                htmlRecipeExportURL = url
                status = "Prepared an HTML cookbook with \(recipes.count) recipes."
            }
        } catch { status = "Could not export recipes: \(error.localizedDescription)" }
    }
}

private struct SafariRecipeImportHistoryView: View {
    let records: [ImportedWebRecipe]

    var body: some View {
        List(records.sorted { $0.capturedAt > $1.capturedAt }, id: \.id) { record in
            if let recipe = record.recipe {
                NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.title).font(.headline)
                        Text("\(recipe.provenance?.tagLabel ?? "Safari") · \(record.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Safari Captures")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PaprikaExportSelectorView: View {
    let recipes: [Recipe]
    let groups: [RecipeLabelGroup]
    let labels: [RecipeLabel]
    let sourceChoices: [PaprikaExportFilterChoice]
    let collectionChoices: [PaprikaExportFilterChoice]
    let onExport: (Set<String>, Set<String>, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLabelIDs: Set<String> = []
    @State private var selectedSourceIDs: Set<String> = []
    @State private var selectedCollectionIDs: Set<String> = []

    private var matchingCount: Int {
        recipes.filter { recipe in
            let matchesSource = selectedSourceIDs.isEmpty || sourceChoices.contains { selectedSourceIDs.contains($0.id) && $0.recipeIDs.contains(recipe.id) }
            let matchesCollection = selectedCollectionIDs.isEmpty || collectionChoices.contains { selectedCollectionIDs.contains($0.id) && $0.recipeIDs.contains(recipe.id) }
            let matchesBrowseLabels = selectedLabelIDs.isEmpty || RecipeLabelFilter.matches(recipe, selectedLabelIDs: selectedLabelIDs, groups: groups, labels: labels)
            return matchesSource && matchesCollection && matchesBrowseLabels
        }.count
    }

    private var isAllSelected: Bool {
        selectedSourceIDs.isEmpty && selectedCollectionIDs.isEmpty && selectedLabelIDs.isEmpty
    }

    var body: some View {
        List {
            Section("Selection") {
                selectionRow(title: "All", isSelected: isAllSelected) { clearSelection() }
            }
            if !sourceChoices.isEmpty {
                Section("Sources") {
                    ForEach(sourceChoices) { choice in
                        selectionRow(title: choice.title, isSelected: selectedSourceIDs.contains(choice.id)) {
                            toggleSource(choice.id)
                        }
                    }
                }
            }
            if !collectionChoices.isEmpty {
                Section("Collections") {
                    ForEach(collectionChoices) { choice in
                        selectionRow(title: choice.title, isSelected: selectedCollectionIDs.contains(choice.id)) {
                            toggleCollection(choice.id)
                        }
                    }
                }
            }
            ForEach(groups) { group in
                Section("\(group.displayName) labels") {
                    ForEach(labels(in: group)) { label in
                        selectionRow(title: label.displayName, isSelected: selectedLabelIDs.contains(label.id)) {
                            toggle(label, in: group)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Recipes to export", value: "\(matchingCount)")
                Button("Clear selection") { clearSelection() }
                    .disabled(isAllSelected)
            } footer: {
                Text("Choose multiple sources or collections to include any of those choices. Source, collection, and recipe label filters combine together. Recipe labels in the same group match any choice; choices across groups must all match.")
            }
        }
        .navigationTitle("Paprika export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Export \(matchingCount)") {
                    onExport(selectedLabelIDs, selectedSourceIDs, selectedCollectionIDs)
                }
                .disabled(matchingCount == 0)
            }
        }
    }

    private func labels(in group: RecipeLabelGroup) -> [RecipeLabel] {
        labels.filter { $0.groupID == group.id }.sorted { $0.order < $1.order }
    }

    private func toggle(_ label: RecipeLabel, in group: RecipeLabelGroup) {
        if group.allowsMultiple {
            if selectedLabelIDs.contains(label.id) { selectedLabelIDs.remove(label.id) }
            else { selectedLabelIDs.insert(label.id) }
        } else {
            selectedLabelIDs = RecipeLabelFilter.togglingSingle(label, selectedLabelIDs: selectedLabelIDs, labels: labels)
        }
    }

    private func toggleSource(_ id: String) {
        if selectedSourceIDs.contains(id) { selectedSourceIDs.remove(id) }
        else { selectedSourceIDs.insert(id) }
    }

    private func toggleCollection(_ id: String) {
        if selectedCollectionIDs.contains(id) { selectedCollectionIDs.remove(id) }
        else { selectedCollectionIDs.insert(id) }
    }

    private func clearSelection() {
        selectedSourceIDs.removeAll()
        selectedCollectionIDs.removeAll()
        selectedLabelIDs.removeAll()
    }

    private func selectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaprikaExportFilterChoice: Identifiable, Hashable {
    let id: String
    let title: String
    var recipeIDs: Set<String>
}

private struct RecipeCategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeCategory.order) private var categories: [RecipeCategory]
    @Query private var settings: [RecipeCategorySettings]
    @Query private var assignments: [RecipeCategoryAssignment]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var importedWebRecords: [ImportedWebRecipe]
    @State private var newCategoryName = ""
    @State private var pendingDeleteID: String?
    @State private var status: String?

    private var defaultCategoryID: String { settings.first?.defaultCategoryID ?? categories.first?.id ?? "" }
    private var allRecipes: [Recipe] { CookbookCatalog.bundled.recipes + importedRecords.compactMap(\.recipe) + importedWebRecords.compactMap(\.recipe) }

    var body: some View {
        List {
            Section("Default for unmatched imports") {
                if categories.isEmpty {
                    Text("Categories are still loading.").foregroundStyle(.secondary)
                } else {
                    Picker("Default category", selection: Binding(get: { defaultCategoryID }, set: setDefaultCategory)) {
                        ForEach(categories.sorted { $0.order < $1.order }) { Text($0.name).tag($0.id) }
                    }
                }
                Text("An imported recipe uses a matching existing category. Recipes with no unique match go to this category.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Categories") {
                ForEach(categories.sorted { $0.order < $1.order }) { category in
                    NavigationLink {
                        RecipeCategoryRenameView(category: category)
                    } label: {
                        HStack {
                            Text(category.name)
                            Spacer()
                            if category.id == defaultCategoryID { Text("Default").font(.caption).foregroundStyle(.secondary) }
                            let count = recipeCount(in: category.id)
                            Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDeleteID = category.id }
                    }
                }
                .onMove(perform: moveCategories)
                HStack {
                    TextField("New category", text: $newCategoryName)
                        .submitLabel(.done)
                        .onSubmit(addCategory)
                    Button("Add", systemImage: "plus", action: addCategory)
                        .labelStyle(.iconOnly)
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar { EditButton() }
        .task {
            do { try RecipeCategoryStore.seedIfNeeded(in: modelContext) }
            catch { status = "Could not load categories: \(error.localizedDescription)" }
        }
        .confirmationDialog(deletePrompt, isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } }), titleVisibility: .visible) {
            if let category = categories.first(where: { $0.id == pendingDeleteID }) {
                let hasRecipes = recipeCount(in: category.id) > 0
                let needsReplacement = hasRecipes || category.id == defaultCategoryID
                if needsReplacement {
                    ForEach(categories.filter { $0.id != category.id }.sorted { $0.order < $1.order }) { replacement in
                        Button("Move to \(replacement.name) and delete", role: .destructive) { delete(category, replacingWith: replacement.id) }
                    }
                } else {
                    Button("Delete Category", role: .destructive) { delete(category, replacingWith: categories.first(where: { $0.id != category.id })?.id) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            if let category = categories.first(where: { $0.id == pendingDeleteID }), recipeCount(in: category.id) > 0 {
                Text("Recipes in \(category.name) will move to the selected category.")
            } else {
                Text("This category will be removed from your Recipes list.")
            }
        }
        .alert("Categories", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
            Button("OK") { status = nil }
        } message: { Text(status ?? "") }
    }

    private var deletePrompt: String {
        guard let category = categories.first(where: { $0.id == pendingDeleteID }) else { return "Delete category?" }
        return "Delete \(category.name)?"
    }

    private func resolvedCategoryID(for recipe: Recipe) -> String {
        if let assignment = assignments.first(where: { assignment in assignment.recipeID == recipe.id && categories.contains(where: { $0.id == assignment.categoryID }) }) { return assignment.categoryID }
        return RecipeCategoryStore.match(sourceNames: [recipe.category], categories: categories)?.id ?? defaultCategoryID
    }

    private func recipeCount(in categoryID: String) -> Int { allRecipes.filter { resolvedCategoryID(for: $0) == categoryID }.count }

    private func setDefaultCategory(_ id: String) {
        do {
            if let record = settings.first { record.defaultCategoryID = id }
            else { modelContext.insert(RecipeCategorySettings(defaultCategoryID: id)) }
            try modelContext.save()
        } catch { status = "Could not update the default category: \(error.localizedDescription)" }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !categories.contains(where: { RecipeCategoryStore.normalized($0.name) == RecipeCategoryStore.normalized(name) }) else { status = "A category with that name already exists."; return }
        modelContext.insert(RecipeCategory(id: "user:\(UUID().uuidString)", name: name, order: (categories.map(\.order).max() ?? -1) + 1))
        do { try modelContext.save(); newCategoryName = "" }
        catch { status = "Could not add the category: \(error.localizedDescription)" }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = categories.sorted { $0.order < $1.order }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() { category.order = index }
        do { try modelContext.save() }
        catch { status = "Could not reorder categories: \(error.localizedDescription)" }
    }

    private func delete(_ category: RecipeCategory, replacingWith replacementID: String?) {
        do { try RecipeCategoryStore.deleteCategory(category.id, replacingWith: replacementID, in: modelContext); pendingDeleteID = nil }
        catch { status = "Could not delete the category: \(error.localizedDescription)" }
    }
}

private struct RecipeCategoryRenameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let category: RecipeCategory
    @State private var name: String
    @State private var status: String?

    init(category: RecipeCategory) {
        self.category = category
        _name = State(initialValue: category.name)
    }

    var body: some View {
        Form {
            Section("Category name") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(save)
                Text("Recipes assigned to this category keep their assignment when it is renamed.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit Category")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) } }
        .alert("Category", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
            Button("OK") { status = nil }
        } message: { Text(status ?? "") }
    }

    private func save() {
        do { try RecipeCategoryStore.renameCategory(category.id, to: name, in: modelContext); dismiss() }
        catch { status = error.localizedDescription }
    }
}

private struct RecipeUsageStatsView: View {
    @Query private var stats: [RecipeUsageStats]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var importedWebRecords: [ImportedWebRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @State private var exportURL: URL?

    private var rows: [(recipe: Recipe?, stats: RecipeUsageStats?)] {
        let deletedIDs = Set(deletedRecipes.map(\.recipeID))
        let catalog = CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe) + importedWebRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
        var byID = Dictionary(uniqueKeysWithValues: stats.map { ($0.recipeID, $0) })
        let catalogRows: [(recipe: Recipe?, stats: RecipeUsageStats?)] = catalog.map { (Optional($0), byID.removeValue(forKey: $0.id)) }
        let unmatched = stats.filter { record in !catalog.contains { $0.id == record.recipeID } }
        return (catalogRows + unmatched.map { (Optional<Recipe>.none, Optional($0)) }).sorted { left, right in
            let leftOpens = left.stats?.recipeOpenCount ?? 0
            let rightOpens = right.stats?.recipeOpenCount ?? 0
            if leftOpens != rightOpens { return leftOpens > rightOpens }
            let leftGroceries = left.stats?.groceryAddFlowCount ?? 0
            let rightGroceries = right.stats?.groceryAddFlowCount ?? 0
            if leftGroceries != rightGroceries { return leftGroceries > rightGroceries }
            return (left.recipe?.title ?? left.stats?.recipeID ?? "") < (right.recipe?.title ?? right.stats?.recipeID ?? "")
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(rows.enumerated()), id: \.offset) { item in
                    let row = item.element
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.recipe?.title ?? "Unknown recipe (\(row.stats?.recipeID ?? ""))").font(.headline)
                        Text("\(row.stats?.recipeOpenCount ?? 0) opens · \(row.stats?.groceryAddFlowCount ?? 0) grocery adds")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let updatedAt = row.stats?.updatedAt {
                            Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                if let exportURL { ShareLink(item: exportURL) { Label("Share CSV export", systemImage: "square.and.arrow.up") } }
                Button("Export counts as CSV") { exportCSV() }
            } footer: {
                Text("Usage counts are local to this device. The export includes every catalog recipe, including zero-count recipes, and preserves IDs no longer present in the catalog.")
            }
        }
        .navigationTitle("Recipe popularity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exportCSV() {
        let formatter = ISO8601DateFormatter()
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = UserFiles.directory.appendingPathComponent("recipe-usage-\(timestamp).csv")
        let lines = ["recipe_id,title,recipe_opens,grocery_add_flows,updated_at"] + rows.map { row in
            let recipeID = row.recipe?.id ?? row.stats?.recipeID ?? ""
            let title = row.recipe?.title ?? "Unknown recipe"
            let updatedAt = row.stats.map { formatter.string(from: $0.updatedAt) } ?? ""
            return [recipeID, title, String(row.stats?.recipeOpenCount ?? 0), String(row.stats?.groceryAddFlowCount ?? 0), updatedAt]
                .map(Self.csvField).joined(separator: ",")
        }
        do { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic); exportURL = url }
        catch { exportURL = nil }
    }

    private static func csvField(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}

private struct PaprikaImportHistoryView: View {
    @Query(sort: \PaprikaImportRun.createdAt, order: .reverse) private var runs: [PaprikaImportRun]

    var body: some View {
        List {
            if runs.isEmpty {
                ContentUnavailableView("No Paprika imports yet", systemImage: "square.and.arrow.down", description: Text("Completed imports will appear here."))
            } else {
                ForEach(runs) { run in PaprikaImportRunRow(run: run) }
            }
        }
        .navigationTitle("Paprika imports")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PaprikaImportRunRow: View {
    let run: PaprikaImportRun

    var body: some View {
        NavigationLink {
            PaprikaImportRunDetailView(run: run)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("Paprika file · \(run.createdAt.formatted(date: .abbreviated, time: .shortened)) · run \(run.runNumber)")
                    .font(.subheadline.weight(.semibold))
                Text("\(run.importedCount) imported · \(run.skippedCount) skipped\(run.undoneAt == nil ? "" : " · undone")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct PaprikaImportRunDetailView: View {
    let run: PaprikaImportRun
    @Query private var importedRecords: [ImportedPaprikaRecipe]

    private var summary: PaprikaImportSummary {
        let recipesByID = Dictionary(uniqueKeysWithValues: importedRecords.compactMap { record in
            record.recipe.map { (record.id, $0.title) }
        })
        let titles = run.importedRecipeIDs.compactMap { recipesByID[$0] }
        return PaprikaImportSummary(runID: run.id, labelID: run.labelID, displayName: run.displayName, importedTitles: titles, skippedRecipes: run.skippedRecipes, wasUndone: run.undoneAt != nil)
    }

    var body: some View {
        PaprikaImportSummaryContent(summary: summary)
            .navigationTitle("Import Summary")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReminderListChoice: Identifiable { let id: String; let title: String }

private struct SettingsGroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .listRowSeparator(.hidden)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return encoder }
}

struct OpenAIKeySettingsSection: View {
    @State private var credential = ""
    @State private var hasSavedKey = false
    @State private var message = ""

    var body: some View {
        Group {
            SettingsGroupLabel(title: "OpenAI API key")
            Text(hasSavedKey ? "An API key is saved in this device’s Keychain." : "No API key is saved on this device.")
                .font(.footnote).foregroundStyle(.secondary)
            SecureField("Paste personal API key", text: $credential)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(saveKey)
            Button("Save API key", action: saveKey)
                .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Remove API key", role: .destructive, action: removeKey)
                .disabled(!hasSavedKey)
            Link("Create or manage an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
            Text("This shared credential is used by recipe image generation and dinner planning. It is stored in Keychain.")
                .font(.footnote).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .onAppear(perform: refreshStatus)
    }

    private func saveKey() {
        let key = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        KeychainKey.store(key)
        credential = ""
        hasSavedKey = true
        message = "Saved in Keychain."
    }

    private func removeKey() {
        KeychainKey.delete()
        credential = ""
        hasSavedKey = false
        message = "Removed from Keychain."
    }

    private func refreshStatus() {
        hasSavedKey = !KeychainKey.read().isEmpty
    }
}

enum KeychainKey {
    private static let service = "com.cseibert.Cookbook.OpenAI"
    static func store(_ value: String) {
        delete(); guard !value.isEmpty else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key", kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(query as CFDictionary, nil)
    }
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }; return String(decoding: data, as: UTF8.self)
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"] as CFDictionary)
    }
}

private struct DinnerDateGroup: Identifiable {
    let date: Date
    let entries: [PlannedDinnerRecipe]
    let savedTimelines: [DinnerTimeline]
    var id: Date { date }
}

private struct GroceryReviewSession: Identifiable {
    let id = UUID()
    let recipes: [Recipe]
}

struct DinnerPlannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedDinnerRecipe.dinnerDate) private var scheduled: [PlannedDinnerRecipe]
    @Query(sort: \DinnerTimeline.updatedAt, order: .reverse) private var saved: [DinnerTimeline]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var importedWebRecords: [ImportedWebRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @State private var selectedIDs = Set<String>()
    @State private var dinnerTime = Date.now
    @State private var plan: [TimelineActivity] = []
    @State private var planName = "Dinner"
    @State private var showingPlan = false
    @State private var editingTimelineID: UUID?
    @State private var status: String?
    @State private var showingChecklistOverflow = false
    @State private var showingCookingRun = false
    @State private var generatingDinnerDate: Date?
    @State private var groceryReviewSession: GroceryReviewSession?
    @State private var checklistShareFile: TimelineShareFile?
    @State private var checklistError: String?
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openAIModel") private var openAIModel = "gpt-6-astra"
    private var recipes: [Recipe] {
        let deletedIDs = Set(deletedRecipes.map(\.recipeID))
        return CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe) + importedWebRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
    }

    private var recipeTitles: [String: String] { Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) }) }
    private var dinnerGroups: [DinnerDateGroup] {
        let calendar = Calendar.current
        let dates = Set(scheduled.map { calendar.startOfDay(for: $0.dinnerDate) })
            .union(saved.map { calendar.startOfDay(for: $0.targetDate) })
        return dates.map { date in
            DinnerDateGroup(
                date: date,
                entries: scheduled.filter { calendar.isDate($0.dinnerDate, inSameDayAs: date) }.sorted { $0.dinnerDate < $1.dinnerDate },
                savedTimelines: saved.filter { calendar.isDate($0.targetDate, inSameDayAs: date) }.sorted { $0.updatedAt > $1.updatedAt }
            )
        }.sorted { $0.date > $1.date }
    }
    private var timelineDayGroups: [TimelineDayGroup] {
        let grouped = Dictionary(grouping: plan.indices) { dayOffset(for: plan[$0].start) }
        return grouped.keys.sorted(by: >).map { TimelineDayGroup(offset: $0, activityIndices: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if dinnerGroups.isEmpty {
                    Section("Dinner dates") {
                        ContentUnavailableView("No dinners planned", systemImage: "calendar.badge.plus", description: Text("Open a recipe, tap the ellipsis, and choose Add to Dinner."))
                    }
                }
                ForEach(dinnerGroups) { group in
                    Section(group.date.formatted(date: .complete, time: .omitted)) {
                        ForEach(group.entries) { entry in
                            Group {
                                if let recipe = recipes.first(where: { $0.id == entry.recipeID }) {
                                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                        dinnerRecipeLabel(title: recipe.title, date: entry.dinnerDate)
                                    }
                                } else {
                                    dinnerRecipeLabel(title: recipeTitles[entry.recipeID] ?? entry.recipeID, date: entry.dinnerDate)
                                }
                            }
                            .contextMenu { Button("Remove from dinner", systemImage: "trash", role: .destructive) { context.delete(entry) } }
                        }
                        if !group.entries.isEmpty && group.savedTimelines.isEmpty {
                            Button { Task { await generateWithAI(for: group.entries) } } label: {
                                if generatingDinnerDate == Calendar.current.startOfDay(for: group.date) { ProgressView("Planning…") } else { Label("Generate work-back plan", systemImage: "sparkles") }
                            }.disabled(generatingDinnerDate != nil)
                        }
                        if !group.entries.isEmpty || !group.savedTimelines.isEmpty {
                            Button {
                                let activities = group.savedTimelines.flatMap(\.activities)
                                let ids = group.entries.map(\.recipeID) + group.savedTimelines.flatMap(savedRecipeIDs)
                                let titles = group.entries.compactMap { recipeTitles[$0.recipeID] } + activities.map(\.recipeTitle)
                                openGroceries(for: ids, titles: titles, activities: activities)
                            } label: { Label("Add to Groceries", systemImage: "cart") }
                        }
                        ForEach(group.savedTimelines) { timeline in
                            HStack {
                                Button { openTimeline(timeline); showingPlan = true } label: {
                                    VStack(alignment: .leading) {
                                        Text(timeline.name)
                                        Text(savedDinnerSummary(timeline)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                Button { openTimeline(timeline); showingCookingRun = true } label: {
                                    Label("Play", systemImage: "play.fill").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                                }.buttonStyle(.bordered).accessibilityLabel("Play \(timeline.name)")
                            }
                            .contextMenu {
                                Button("Print dinner", systemImage: "printer") { openTimeline(timeline); showingPlan = true }
                                Button("Duplicate for next year", systemImage: "doc.on.doc") { duplicate(timeline) }
                                Button("Delete saved dinner", systemImage: "trash", role: .destructive) { context.delete(timeline) }
                            }
                        }
                    }
                }
                Section { Text("Choose recipes from Recipes and assign them to a dinner date. Generate a work-back plan from that date; saved plans appear with their dinner date.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Dinner")
            .sheet(isPresented: $showingPlan) { timelineSheet }
            .sheet(item: $groceryReviewSession) { session in GroceryReviewView(recipes: session.recipes) }
            .fullScreenCover(isPresented: $showingCookingRun) { DinnerTimelineCookingView(activities: $plan, dinnerTime: dinnerTime) }
            .onChange(of: plan.map(\.isComplete)) { _, _ in persistCompletionIfNeeded() }
            .alert("Dinner plan", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) { Button("OK") { status = nil } } message: { Text(status ?? "") }
        }
    }

    private var timelineSheet: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Dinner name", text: $planName)
                    Button { showingCookingRun = true } label: { Label("Play dinner steps", systemImage: "play.fill") }
                        .disabled(plan.isEmpty)
                }
                ForEach(timelineDayGroups) { group in
                    Section(group.title) {
                        ForEach(group.activityIndices, id: \.self) { index in
                            TimelineActivityRow(activity: $plan[index])
                        }
                    }
                }
            }
            .navigationTitle(planName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button { makeChecklist() } label: { Label("Print", systemImage: "printer") } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { saveTimeline() } }
            }
            .sheet(item: $checklistShareFile) { file in ActivityView(items: [file.url]) }
            .alert("Print dinner", isPresented: Binding(get: { checklistError != nil }, set: { if !$0 { checklistError = nil } })) { Button("OK") { checklistError = nil } } message: { Text(checklistError ?? "") }
            .alert("Could not print dinner", isPresented: $showingChecklistOverflow) { Button("OK") { } } message: { Text("The checklist PDF could not be created as a readable one-page document. Shorten instructions or remove activities, then try again. The saved timeline remains unchanged until you choose Done.") }
        }
    }

    @MainActor private func generateWithAI(for entries: [PlannedDinnerRecipe]) async {
        prepare(entries)
        let chosen = recipes.filter { selectedIDs.contains($0.id) }
        let groupDate = Calendar.current.startOfDay(for: entries.first?.dinnerDate ?? .now)
        generatingDinnerDate = groupDate
        defer { generatingDinnerDate = nil }
        do {
            let estimates: [AIActivityEstimate]
            if aiProvider == "on-device" {
                estimates = try await OnDeviceDinnerPlanner.estimateActivities(recipes: chosen)
            } else {
                estimates = try await AIDinnerPlanner.estimateActivities(recipes: chosen, model: openAIModel, key: KeychainKey.read())
            }
            let estimateByID = Dictionary(uniqueKeysWithValues: estimates.map { ("\($0.recipeID):\($0.stepID)", $0) })
            buildTimeline(recipes: chosen, duration: { recipe, step in estimateByID["\(recipe.id):\(step.id)"]!.durationMinutes }, active: { recipe, step in estimateByID["\(recipe.id):\(step.id)"]!.active }, overlapEligible: { recipe, step in estimateByID["\(recipe.id):\(step.id)"]!.overlapEligible }, label: { _, _ in "AI estimate" })
        } catch { status = error.localizedDescription }
    }

    private func prepare(_ entries: [PlannedDinnerRecipe]) {
        selectedIDs = Set(entries.map(\.recipeID))
        dinnerTime = entries.first?.dinnerDate ?? .now
        let chosen = recipes.filter { selectedIDs.contains($0.id) }
        planName = generatedPlanName(for: chosen, dinnerTime: dinnerTime)
        editingTimelineID = nil
    }

    private func buildTimeline(recipes chosen: [Recipe], duration: (Recipe, RecipeStep) -> Int, active: (Recipe, RecipeStep) -> Bool, overlapEligible: (Recipe, RecipeStep) -> Bool, label: (Recipe, RecipeStep) -> String) {
        let allSteps = chosen.flatMap { recipe in recipe.steps.map { (recipe, $0) } }
        guard !allSteps.isEmpty else { status = "These recipes do not have any parsed instructions yet."; return }
        let estimates = allSteps.map { recipe, step in
            PlannedStep(recipe: recipe, step: step, duration: duration(recipe, step), active: active(recipe, step), overlapEligible: overlapEligible(recipe, step), label: label(recipe, step))
        }
        let result = DinnerTimelineScheduler.schedule(estimates, dinnerTime: dinnerTime)
        plan = result.activities
        status = result.startsInPast ? "This draft starts in the past. Use an earlier preparation day or change dinner time." : nil
        persistTimeline()
        showingPlan = true
    }

    private func saveTimeline() {
        persistTimeline()
        showingPlan = false
    }

    private func persistTimeline() {
        if let editingTimelineID, let existing = saved.first(where: { $0.id == editingTimelineID }) {
            existing.name = planName
            existing.targetDate = dinnerTime
            existing.recipeIDsData = (try? JSONEncoder().encode(Array(selectedIDs))) ?? existing.recipeIDsData
            existing.activitiesData = (try? JSONEncoder().encode(plan)) ?? existing.activitiesData
            existing.updatedAt = .now
        } else {
            let timeline = DinnerTimeline(name: planName, targetDate: dinnerTime, recipeIDs: Array(selectedIDs), activities: plan)
            context.insert(timeline)
            editingTimelineID = timeline.id
        }
    }

    private func openTimeline(_ timeline: DinnerTimeline) {
        plan = timeline.activities
        planName = timeline.name
        dinnerTime = timeline.targetDate
        editingTimelineID = timeline.id
        selectedIDs = Set((try? JSONDecoder().decode([String].self, from: timeline.recipeIDsData)) ?? [])
    }

    private func persistCompletionIfNeeded() {
        guard let editingTimelineID, let timeline = saved.first(where: { $0.id == editingTimelineID }) else { return }
        timeline.activitiesData = (try? JSONEncoder().encode(plan)) ?? timeline.activitiesData
        timeline.updatedAt = .now
    }

    private func dayOffset(for activityDate: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: activityDate), to: Calendar.current.startOfDay(for: dinnerTime)).day ?? 0
    }

    private func duplicate(_ timeline: DinnerTimeline) {
        let calendar = Calendar.current
        guard let nextDinner = calendar.date(byAdding: .year, value: 1, to: timeline.targetDate) else { status = "Could not calculate next year's dinner date."; return }
        let shifted = timeline.activities.map { activity in
            let startOffset = calendar.dateComponents([.day, .hour, .minute], from: timeline.targetDate, to: activity.start)
            let endOffset = calendar.dateComponents([.day, .hour, .minute], from: timeline.targetDate, to: activity.end)
            return TimelineActivity(id: activity.id, recipeTitle: activity.recipeTitle, instruction: activity.instruction, start: calendar.date(byAdding: startOffset, to: nextDinner) ?? activity.start, end: calendar.date(byAdding: endOffset, to: nextDinner) ?? activity.end, active: activity.active, estimateLabel: activity.estimateLabel)
        }
        let recipeIDs = (try? JSONDecoder().decode([String].self, from: timeline.recipeIDsData)) ?? []
        context.insert(DinnerTimeline(name: "\(timeline.name) \(calendar.component(.year, from: nextDinner))", targetDate: nextDinner, recipeIDs: recipeIDs, activities: shifted))
    }

    private func makeChecklist() {
        guard !plan.isEmpty else { checklistError = "This dinner has no saved steps to print."; return }
        guard let url = TimelineChecklistPDF.render(name: planName, dinnerTime: dinnerTime, activities: plan) else { showingChecklistOverflow = true; return }
        checklistShareFile = TimelineShareFile(url: url)
    }

    private func openGroceries(for recipeIDs: [String], titles: [String] = [], activities: [TimelineActivity] = []) {
        let matchingRecipes = resolvedRecipes(
            ids: recipeIDs,
            activityIDs: activities.map(\.id),
            titles: titles + activities.map(\.recipeTitle)
        )
        groceryReviewSession = GroceryReviewSession(recipes: matchingRecipes)
    }

    private func resolvedRecipes(ids: [String], activityIDs: [String] = [], titles: [String] = []) -> [Recipe] {
        var resolved: [Recipe] = []
        var seen = Set<String>()
        let idsFromActivities = activityIDs.compactMap { $0.split(separator: ":", maxSplits: 1).first.map(String.init) }
        for id in ids + idsFromActivities {
            if let recipe = recipes.first(where: { $0.id == id }), seen.insert(recipe.id).inserted { resolved.append(recipe) }
        }
        let titleKeys = Set(titles.map(normalizedRecipeTitle))
        for recipe in recipes where titleKeys.contains(normalizedRecipeTitle(recipe.title)) {
            if seen.insert(recipe.id).inserted { resolved.append(recipe) }
        }
        return resolved
    }

    private func normalizedRecipeTitle(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func dinnerRecipeLabel(title: String, date: Date) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func savedRecipeIDs(_ timeline: DinnerTimeline) -> [String] {
        (try? JSONDecoder().decode([String].self, from: timeline.recipeIDsData)) ?? []
    }

    private func generatedPlanName(for chosen: [Recipe], dinnerTime: Date) -> String {
        let base = chosen.map(\.title).joined(separator: " + ")
        let title = base.isEmpty ? "Dinner" : base
        let matching = saved.filter { Calendar.current.isDate($0.targetDate, inSameDayAs: dinnerTime) }.compactMap { timeline -> Int? in
            if timeline.name == title { return 1 }
            let prefix = title + " number "
            guard timeline.name.hasPrefix(prefix), let number = Int(timeline.name.dropFirst(prefix.count)) else { return nil }
            return number
        }
        guard let highest = matching.max() else { return title }
        return "\(title) number \(highest + 1)"
    }

    private func savedDinnerSummary(_ timeline: DinnerTimeline) -> String {
        let dinner = timeline.targetDate.formatted(date: .abbreviated, time: .shortened)
        guard let start = timeline.activities.map(\.start).min() else { return "Dinner \(dinner) · no steps" }
        let minutes = max(0, Int(timeline.targetDate.timeIntervalSince(start) / 60))
        let duration = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return "Dinner \(dinner) · starts \(start.formatted(date: .abbreviated, time: .shortened)) · \(duration)"
    }
}

private struct PlannedStep {
    let recipe: Recipe
    let step: RecipeStep
    let duration: Int
    let active: Bool
    let overlapEligible: Bool
    let label: String
}

private enum DinnerTimelineScheduler {
    static func schedule(_ steps: [PlannedStep], dinnerTime: Date) -> (activities: [TimelineActivity], startsInPast: Bool) {
        var activeCursor = dinnerTime
        var nextStepStartByRecipe: [String: Date] = [:]
        var activities: [TimelineActivity] = []
        for item in steps.reversed() {
            let recipeID = item.recipe.id
            let downstreamStart = nextStepStartByRecipe[recipeID] ?? dinnerTime
            let safeToOverlap = item.overlapEligible && !item.active && !containsSafetyCriticalWait(item.step.originalInstruction)
            let end = safeToOverlap ? downstreamStart : min(activeCursor, downstreamStart)
            let start = end.addingTimeInterval(TimeInterval(-max(1, item.duration) * 60))
            if !safeToOverlap { activeCursor = start }
            nextStepStartByRecipe[recipeID] = start
            activities.append(TimelineActivity(
                id: "\(recipeID):\(item.step.id)", recipeTitle: item.recipe.title,
                instruction: item.step.originalInstruction, start: start, end: end,
                active: item.active, estimateLabel: item.label
            ))
        }
        let ordered = activities.sorted { $0.start < $1.start }
        return (ordered, (ordered.first?.start ?? dinnerTime) < Date())
    }

    private static func containsSafetyCriticalWait(_ instruction: String) -> Bool {
        let text = instruction.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let terms = ["rest", "cool", "chill", "refrigerat", "marinat", "overnight", "proof", "rise", "thermometer", "internal temperature", "until", "at least"]
        return terms.contains { text.contains($0) }
    }
}

private struct TimelineShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct TimelineDayGroup: Identifiable {
    let offset: Int
    let activityIndices: [Int]
    var id: Int { offset }
    var title: String {
        switch offset {
        case 0: "Today"
        case 1: "Yesterday"
        case 2: "2 days before"
        case let days where days > 2: "\(days) days before"
        default: "After dinner"
        }
    }
}

private struct TimelineActivityRow: View {
    @Binding var activity: TimelineActivity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { activity.isComplete.toggle() } label: {
                Image(systemName: activity.isComplete ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundStyle(activity.isComplete ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activity.isComplete ? "Mark step incomplete" : "Mark step complete")
            VStack(alignment: .leading, spacing: 5) {
                Text(activity.start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(activity.recipeTitle).font(.headline)
                TextField("Checklist instruction", text: $activity.instruction, axis: .vertical).font(.subheadline).lineLimit(2...6)
                Text(activity.estimateLabel + (activity.active ? " · active" : " · passive")).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .opacity(activity.isComplete ? 0.62 : 1)
    }
}

private struct DinnerTimelineCookingView: View {
    @Binding var activities: [TimelineActivity]
    let dinnerTime: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentIndex = 0

    private var current: TimelineActivity? { activities.indices.contains(currentIndex) ? activities[currentIndex] : nil }
    private var completedCount: Int { activities.filter(\.isComplete).count }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                if let current {
                    Text("STEP \(currentIndex + 1) OF \(activities.count)").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.secondary)
                    ProgressView(value: Double(completedCount), total: Double(max(activities.count, 1)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(dayTitle(for: current.start)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Text(current.start.formatted(date: .omitted, time: .shortened)).font(.title3.weight(.medium))
                            Text(current.recipeTitle).font(.system(.title2, design: .serif).weight(.semibold))
                            Text(current.instruction).font(.system(.title, design: .serif)).fixedSize(horizontal: false, vertical: true).lineSpacing(5)
                            Text(current.estimateLabel + (current.active ? " · active" : " · passive")).font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                    Button { activities[currentIndex].isComplete.toggle() } label: {
                        Label(activities[currentIndex].isComplete ? "Mark incomplete" : "Mark complete", systemImage: activities[currentIndex].isComplete ? "checkmark.square.fill" : "square")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }.buttonStyle(.bordered)
                    HStack(spacing: 14) {
                        Button { currentIndex = max(0, currentIndex - 1) } label: { Label("Previous", systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(.bordered).disabled(currentIndex == 0)
                        Button { if currentIndex + 1 < activities.count { currentIndex += 1 } else { dismiss() } } label: { HStack { Text(currentIndex + 1 == activities.count ? "Finish" : "Next"); Image(systemName: "chevron.right") }.frame(maxWidth: .infinity, minHeight: 52) }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView("No dinner steps", systemImage: "checklist")
                }
            }
            .padding(22)
            .navigationTitle("Dinner mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                currentIndex = activities.firstIndex(where: { !$0.isComplete }) ?? max(activities.count - 1, 0)
                setAwake(scenePhase == .active)
            }
            .onChange(of: scenePhase) { _, phase in setAwake(phase == .active) }
            .onDisappear { setAwake(false) }
        }
    }

    private func dayTitle(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: dinnerTime)).day ?? 0
        return switch days {
        case 0: "Today"
        case 1: "Yesterday"
        case let value where value > 1: "\(value) days before"
        default: "After dinner"
        }
    }

    private func setAwake(_ awake: Bool) { UIApplication.shared.isIdleTimerDisabled = awake }
}
