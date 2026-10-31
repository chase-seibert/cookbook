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
    @State private var paprikaExportURL: URL?
    @State private var exportingPaprika = false
    @State private var markdownURL: URL?
    @State private var showingPaprikaImporter = false
    @State private var importReview: PaprikaImportReviewSession?
    @Query(sort: \RecipeNote.updatedAt, order: .reverse) private var notes: [RecipeNote]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @Query(sort: \PaprikaImportRun.createdAt, order: .reverse) private var paprikaImportRuns: [PaprikaImportRun]
    @Query private var recipePhotos: [RecipePhoto]
    private let reminderStore = EKEventStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("Groceries") {
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
                Section("Recipe notes") {
                    Text("\(notes.filter { $0.deletedAt == nil }.count) saved notes")
                    Button("Export notes with timestamps") { exportNotes() }
                    if let exportURL { ShareLink(item: exportURL) { Label("Share JSON export", systemImage: "square.and.arrow.up") } }
                    if let markdownURL { ShareLink(item: markdownURL) { Label("Share Markdown companion", systemImage: "doc.text") } }
                    Text("Exports preserve each note's original text, recipe ID, optional step ID, and creation/update timestamps.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recipe imports") {
                    Button { showingPaprikaImporter = true } label: { Label("Import Paprika recipes…", systemImage: "square.and.arrow.down") }
                    Text("Review recipes before adding them. Paprika imports stay on this device and are marked internally.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(paprikaImportRuns.prefix(3), id: \.id) { run in PaprikaImportRunRow(run: run) }
                    if paprikaImportRuns.count > 3 {
                        NavigationLink("All Paprika import runs (\(paprikaImportRuns.count))") { PaprikaImportHistoryView() }
                    }
                    NavigationLink {
                        RecipeBrowserView(showingDeletedRecipes: true, managesNavigationStack: false, screenTitle: "Deleted recipes")
                    } label: {
                        Label("Deleted recipes (\(importedRecords.filter { $0.deletedAt != nil }.count + deletedRecipes.count))", systemImage: "trash")
                    }
                }
                Section("Paprika export") {
                    Button { Task { await exportAllPaprikaRecipes() } } label: {
                        Label(exportingPaprika ? "Preparing export…" : "Export all recipes", systemImage: "square.and.arrow.up")
                    }.disabled(exportingPaprika)
                    if let paprikaExportURL {
                        ShareLink(item: paprikaExportURL) { Label("Share Paprika collection", systemImage: "square.and.arrow.up") }
                    }
                    Text("Exports all active bundled and imported recipes, regardless of browse filters.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recipe usage") {
                    NavigationLink {
                        RecipeUsageStatsView()
                    } label: {
                        Label("Recipe popularity counts", systemImage: "chart.bar")
                    }
                    Text("Counts are stored on this device only. They are a local usage signal, not cross-user popularity data.").font(.footnote).foregroundStyle(.secondary)
                }
                OpenAIKeySettingsSection()
                Section("Recipe images") {
                    NavigationLink {
                        ImageGenerationSettingsView()
                    } label: {
                        Label("Generate missing recipe covers", systemImage: "sparkles")
                    }
                    Text("Choose an image provider and review or undo previous batch runs.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Dinner planning") {
                    Picker("AI provider", selection: $aiProvider) { Text("OpenAI (cloud)").tag("openai"); Text("On-device").tag("on-device") }
                    if aiProvider == "openai" {
                        TextField("Model", text: $openAIModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        Text("Requires iOS 26 or later, an Apple Intelligence-capable iPhone, Apple Intelligence enabled, a supported language and region, and the on-device model ready. The plan is generated on this iPhone; there is no cloud fallback.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Provider choice is explicit. The on-device option never falls back to the cloud.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") { LabeledContent("Recipe catalog", value: "\(CookbookCatalog.bundled.recipes.count - deletedRecipes.count + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe).count) recipes · offline") }
            }
            .navigationTitle("Settings")
            .onAppear { reminderListName = UserDefaults.standard.string(forKey: "reminderListName") ?? "Not selected" }
            .fileImporter(isPresented: $showingPaprikaImporter, allowedContentTypes: PaprikaFileType.supported, allowsMultipleSelection: false, onCompletion: handlePaprikaSelection)
            .sheet(item: $importReview, onDismiss: openNextPendingPaprikaShare) { session in PaprikaImportReviewView(session: session) }
            .onChange(of: incomingPaprikaURL) { _, url in
                guard let url else { return }
                incomingPaprikaURL = nil
                importPaprikaFile(url)
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
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            Task {
                do {
                    let drafts = try await Task.detached(priority: .userInitiated) { try PaprikaImportReader.parse(data: data) }.value
                    PaprikaShareInbox.removeIfPending(url)
                    guard !drafts.isEmpty else { status = "This Paprika file contains no importable recipes."; return }
                    importReview = PaprikaImportReviewSession(drafts: drafts)
                } catch is CancellationError { return }
                catch {
                    PaprikaShareInbox.removeIfPending(url)
                    status = error.localizedDescription
                }
            }
        } catch { status = "Could not open the selected file: \(error.localizedDescription)" }
    }

    private func openNextPendingPaprikaShare() {
        guard incomingPaprikaURL == nil, let nextURL = PaprikaShareInbox.nextPendingURL() else { return }
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
        let allRecipes = CookbookCatalog.bundled.recipes + importedRecords.compactMap(\.recipe)
        let titles = Dictionary(uniqueKeysWithValues: allRecipes.map { ($0.id, $0.title) })
        let body = records.map { record in
            "## \(titles[record.recipeID] ?? record.recipeID)\n\n- Note ID: `\(record.id.uuidString)`\n- Recipe ID: `\(record.recipeID)`\n- Step ID: \(record.stepID ?? "whole recipe")\n- Created: \(record.createdAt)\n- Updated: \(record.updatedAt)\n\n\(record.text)"
        }.joined(separator: "\n\n---\n\n")
        do { try json.write(to: path, options: .atomic); try Data(("# Cookbook notes\n\n" + body + "\n").utf8).write(to: markdownPath, options: .atomic); exportURL = path; self.markdownURL = markdownPath } catch { status = "Could not export notes: \(error.localizedDescription)" }
    }

    @MainActor private func exportAllPaprikaRecipes() async {
        exportingPaprika = true
        defer { exportingPaprika = false }
        do {
            let deletedIDs = Set(deletedRecipes.map(\.recipeID))
            let recipes = CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
            guard !recipes.isEmpty else { throw PaprikaExportError.noRecipes }
            let items = try recipes.map { try PaprikaExporter.item(for: $0, importedRecords: importedRecords, photos: recipePhotos) }
            let url = PaprikaExporter.temporaryURL(extension: "paprikarecipes")
            try await Task.detached(priority: .userInitiated) { try PaprikaExporter.writeCollection(items, to: url) }.value
            paprikaExportURL = url
            status = "Prepared a Paprika export with \(items.count) recipes."
        } catch { status = "Could not export Paprika recipes: \(error.localizedDescription)" }
    }
}

private struct RecipeUsageStatsView: View {
    @Query private var stats: [RecipeUsageStats]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @State private var exportURL: URL?

    private var rows: [(recipe: Recipe?, stats: RecipeUsageStats?)] {
        let deletedIDs = Set(deletedRecipes.map(\.recipeID))
        let catalog = CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
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

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return encoder }
}

struct OpenAIKeySettingsSection: View {
    @State private var credential = ""
    @State private var hasSavedKey = false
    @State private var message = ""

    var body: some View {
        Section("OpenAI API key") {
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
        return CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + importedRecords.filter { $0.deletedAt == nil }.compactMap(\.recipe)
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
