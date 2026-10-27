import SwiftUI
import SwiftData
import EventKit
import Security
import UIKit

struct SettingsView: View {
    @AppStorage("reminderListID") private var reminderListID = ""
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openAIModel") private var openAIModel = "gpt-6-astra"
    @State private var reminderListName = "Not selected"
    @State private var reminderLists: [ReminderListChoice] = []
    @State private var status: String?
    @State private var exportURL: URL?
    @State private var markdownURL: URL?
    @State private var personalCredential = ""
    @Query(sort: \RecipeNote.updatedAt, order: .reverse) private var notes: [RecipeNote]
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
                Section("Recipe usage") {
                    NavigationLink {
                        RecipeUsageStatsView()
                    } label: {
                        Label("Recipe popularity counts", systemImage: "chart.bar")
                    }
                    Text("Counts are stored on this device only. They are a local usage signal, not cross-user popularity data.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Dinner planning") {
                    Picker("AI provider", selection: $aiProvider) { Text("OpenAI (cloud)").tag("openai"); Text("On-device").tag("on-device") }
                    if aiProvider == "openai" {
                        TextField("Model", text: $openAIModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Personal OpenAI API key", text: $personalCredential).textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit { KeychainKey.store(personalCredential) }
                        Button("Save key") { KeychainKey.store(personalCredential); status = "Saved in iPhone Keychain." }
                        Button("Remove key", role: .destructive) { personalCredential = ""; KeychainKey.delete(); status = "Removed from Keychain." }
                    } else {
                        Text("Requires iOS 26 or later, an Apple Intelligence-capable iPhone, Apple Intelligence enabled, a supported language and region, and the on-device model ready. The plan is generated on this iPhone; there is no cloud fallback.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Provider choice is explicit. The on-device option never falls back to the cloud.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") { LabeledContent("Recipe catalog", value: "\(CookbookCatalog.bundled.recipes.count) recipes · offline") }
            }
            .navigationTitle("Settings")
            .onAppear { reminderListName = UserDefaults.standard.string(forKey: "reminderListName") ?? "Not selected"; loadCredential() }
            .alert("Cookbook", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) { Button("OK") { status = nil } } message: { Text(status ?? "") }
        }
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

    private func loadCredential() { let stored = KeychainKey.read(); personalCredential = stored }

    private func exportNotes() {
        struct NoteExport: Codable { let id: UUID; let recipeID: String; let stepID: String?; let text: String; let createdAt: String; let updatedAt: String; let catalogHash: String }
        let formatter = ISO8601DateFormatter()
        let records = notes.filter { $0.deletedAt == nil }.map { NoteExport(id: $0.id, recipeID: $0.recipeID, stepID: $0.stepID, text: $0.text, createdAt: formatter.string(from: $0.createdAt), updatedAt: formatter.string(from: $0.updatedAt), catalogHash: $0.catalogHash) }
        let stamp = Int(Date().timeIntervalSince1970)
        let path = UserFiles.directory.appendingPathComponent("recipe-notes-\(stamp).json")
        let markdownPath = UserFiles.directory.appendingPathComponent("recipe-notes-\(stamp).md")
        let json = (try? JSONEncoder.pretty.encode(records)) ?? Data("[]".utf8)
        let titles = Dictionary(uniqueKeysWithValues: CookbookCatalog.bundled.recipes.map { ($0.id, $0.title) })
        let body = records.map { record in
            "## \(titles[record.recipeID] ?? record.recipeID)\n\n- Note ID: `\(record.id.uuidString)`\n- Recipe ID: `\(record.recipeID)`\n- Step ID: \(record.stepID ?? "whole recipe")\n- Created: \(record.createdAt)\n- Updated: \(record.updatedAt)\n\n\(record.text)"
        }.joined(separator: "\n\n---\n\n")
        do { try json.write(to: path, options: .atomic); try Data(("# Cookbook notes\n\n" + body + "\n").utf8).write(to: markdownPath, options: .atomic); exportURL = path; self.markdownURL = markdownPath } catch { status = "Could not export notes: \(error.localizedDescription)" }
    }
}

private struct RecipeUsageStatsView: View {
    @Query private var stats: [RecipeUsageStats]
    @State private var exportURL: URL?

    private var rows: [(recipe: Recipe?, stats: RecipeUsageStats?)] {
        let catalog = CookbookCatalog.bundled.recipes
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

private struct ReminderListChoice: Identifiable { let id: String; let title: String }

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return encoder }
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
    var id: Date { date }
}

struct DinnerPlannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedDinnerRecipe.dinnerDate) private var scheduled: [PlannedDinnerRecipe]
    @Query(sort: \DinnerTimeline.updatedAt, order: .reverse) private var saved: [DinnerTimeline]
    @State private var selectedIDs = Set<String>()
    @State private var dinnerTime = Date.now
    @State private var plan: [TimelineActivity] = []
    @State private var planName = "Dinner"
    @State private var showingPlan = false
    @State private var editingTimelineID: UUID?
    @State private var status: String?
    @State private var checklistURL: URL?
    @State private var showingChecklistOverflow = false
    @State private var showingCookingRun = false
    @State private var isGenerating = false
    @AppStorage("aiProvider") private var aiProvider = "openai"
    @AppStorage("openAIModel") private var openAIModel = "gpt-6-astra"
    private let recipes = CookbookCatalog.bundled.recipes

    private var recipeTitles: [String: String] { Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) }) }
    private var dinnerGroups: [DinnerDateGroup] {
        Dictionary(grouping: scheduled, by: { Calendar.current.startOfDay(for: $0.dinnerDate) })
            .map { DinnerDateGroup(date: $0.key, entries: $0.value.sorted { $0.addedAt < $1.addedAt }) }
            .sorted { $0.date < $1.date }
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
                            HStack {
                                Text(recipeTitles[entry.recipeID] ?? entry.recipeID)
                                Spacer()
                                Text(entry.dinnerDate.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            .contextMenu { Button("Remove from dinner", systemImage: "trash", role: .destructive) { context.delete(entry) } }
                        }
                        Button { Task { await generateWithAI(for: group.entries) } } label: {
                            if isGenerating { ProgressView("Planning…") } else { Label("Generate work-back plan", systemImage: "sparkles") }
                        }.disabled(isGenerating)
                        Button("Build manual draft") { buildManualDraft(for: group.entries) }.disabled(isGenerating)
                    }
                }
                if !saved.isEmpty {
                    Section("Saved dinners") {
                        ForEach(saved) { timeline in
                            HStack {
                                Button { openTimeline(timeline); showingPlan = true } label: {
                                    VStack(alignment: .leading) {
                                        Text(timeline.name)
                                        Text(timeline.targetDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                Button { openTimeline(timeline); showingCookingRun = true } label: {
                                    Label("Play", systemImage: "play.fill").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                                }.buttonStyle(.bordered).accessibilityLabel("Play \(timeline.name)")
                            }
                            .contextMenu {
                                Button("Duplicate for next year", systemImage: "doc.on.doc") { duplicate(timeline) }
                                Button("Delete saved dinner", systemImage: "trash", role: .destructive) { context.delete(timeline) }
                            }
                        }
                    }
                }
                Section { Text("Choose recipes from Recipes and assign them to a dinner date. Generate a work-back plan from that date, review the estimates, then save it in Saved dinners.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Dinner")
            .sheet(isPresented: $showingPlan) { timelineSheet }
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
                ToolbarItem(placement: .cancellationAction) { Button("Close") { showingPlan = false } }
                ToolbarItem(placement: .primaryAction) { Button { makeChecklist() } label: { Label("Checklist PDF", systemImage: "printer") } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveTimeline() } }
                if let checklistURL { ToolbarItem(placement: .secondaryAction) { ShareLink(item: checklistURL) { Label("Share / Print", systemImage: "square.and.arrow.up") } } }
            }
            .alert("One-page checklist", isPresented: $showingChecklistOverflow) { Button("OK") { } } message: { Text("This timeline does not fit on one readable page. Shorten checklist instructions or remove activities, then try again. The saved timeline remains unchanged until you save your edits.") }
        }
    }

    @MainActor private func generateWithAI(for entries: [PlannedDinnerRecipe]) async {
        prepare(entries)
        let chosen = recipes.filter { selectedIDs.contains($0.id) }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let estimates: [AIActivityEstimate]
            if aiProvider == "on-device" {
                estimates = try await OnDeviceDinnerPlanner.estimateActivities(recipes: chosen)
            } else {
                estimates = try await AIDinnerPlanner.estimateActivities(recipes: chosen, model: openAIModel, key: KeychainKey.read())
            }
            let estimateByID = Dictionary(uniqueKeysWithValues: estimates.map { ("\($0.recipeID):\($0.stepID)", $0) })
            buildTimeline(recipes: chosen, duration: { recipe, step in estimateByID["\(recipe.id):\(step.id)"]!.durationMinutes }, active: { recipe, step in estimateByID["\(recipe.id):\(step.id)"]!.active }, label: { _, _ in "AI estimate" })
        } catch { status = error.localizedDescription }
    }

    private func prepare(_ entries: [PlannedDinnerRecipe]) {
        selectedIDs = Set(entries.map(\.recipeID))
        dinnerTime = entries.first?.dinnerDate ?? .now
        planName = "Dinner · " + dinnerTime.formatted(date: .abbreviated, time: .omitted)
        editingTimelineID = nil
    }

    private func buildManualDraft(for entries: [PlannedDinnerRecipe]) {
        prepare(entries)
        let chosen = recipes.filter { selectedIDs.contains($0.id) }
        buildTimeline(recipes: chosen, duration: { _, step in step.durationMinutes ?? 15 }, active: { _, step in step.active }, label: { _, step in step.durationMinutes == nil ? "15 min manual estimate" : "\(step.durationMinutes!) min from source" })
    }

    private func buildTimeline(recipes chosen: [Recipe], duration: (Recipe, RecipeStep) -> Int, active: (Recipe, RecipeStep) -> Bool, label: (Recipe, RecipeStep) -> String) {
        let allSteps = chosen.flatMap { recipe in recipe.steps.map { (recipe, $0) } }
        guard !allSteps.isEmpty else { status = "These recipes do not have any parsed instructions yet."; return }
        var cursor = dinnerTime
        var result: [TimelineActivity] = []
        for (recipe, step) in allSteps.reversed() {
            let minutes = duration(recipe, step)
            let end = cursor
            cursor = cursor.addingTimeInterval(TimeInterval(-minutes * 60))
            result.append(TimelineActivity(id: "\(recipe.id):\(step.id)", recipeTitle: recipe.title, instruction: step.originalInstruction, start: cursor, end: end, active: active(recipe, step), estimateLabel: label(recipe, step)))
        }
        plan = result.reversed()
        status = cursor < Date() ? "This draft starts in the past. Use an earlier preparation day or change dinner time." : nil
        showingPlan = true
    }

    private func saveTimeline() {
        if let editingTimelineID, let existing = saved.first(where: { $0.id == editingTimelineID }) {
            existing.name = planName
            existing.targetDate = dinnerTime
            existing.recipeIDsData = (try? JSONEncoder().encode(Array(selectedIDs))) ?? existing.recipeIDsData
            existing.activitiesData = (try? JSONEncoder().encode(plan)) ?? existing.activitiesData
            existing.updatedAt = .now
        } else {
            context.insert(DinnerTimeline(name: planName, targetDate: dinnerTime, recipeIDs: Array(selectedIDs), activities: plan))
        }
        showingPlan = false
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
        guard let url = TimelineChecklistPDF.render(name: planName, dinnerTime: dinnerTime, activities: plan) else { showingChecklistOverflow = true; return }
        checklistURL = url
    }
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
