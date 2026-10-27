import SwiftUI
import SwiftData
import EventKit
import UIKit

struct CookingModeView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [CookingSessionRecord]
    @State private var stepIndex = 0
    private var step: RecipeStep { recipe.steps[stepIndex] }
    private var currentIngredients: [RecipeIngredient] { recipe.ingredients.filter { step.ingredientIDs.contains($0.id) } }
    private var sections: [String] { Array(NSOrderedSet(array: recipe.steps.map { $0.sectionTitle.isEmpty ? recipe.title : $0.sectionTitle })) as? [String] ?? [recipe.title] }
    private var currentSection: String { step.sectionTitle.isEmpty ? recipe.title : step.sectionTitle }
    private var stepsInCurrentSection: [Int] { recipe.steps.indices.filter { (recipe.steps[$0].sectionTitle.isEmpty ? recipe.title : recipe.steps[$0].sectionTitle) == currentSection } }

    init(recipe: Recipe) {
        self.recipe = recipe
        let recipeID = recipe.id
        _sessions = Query(filter: #Predicate<CookingSessionRecord> { $0.recipeID == recipeID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(recipe.title).font(.headline); Spacer(); Button("Done") { dismiss() }.font(.headline) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections, id: \.self) { section in
                        Button(section) { openSection(section) }
                            .font(.subheadline.weight(section == currentSection ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(section == currentSection ? Color.primary : Color(uiColor: .secondarySystemBackground), in: Capsule())
                            .foregroundStyle(section == currentSection ? Color(uiColor: .systemBackground) : Color.primary)
                    }
                }
            }
            Text("\(currentSection.uppercased()) · STEP \((stepsInCurrentSection.firstIndex(of: stepIndex) ?? 0) + 1) OF \(stepsInCurrentSection.count)").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(currentIngredients) { ingredient in HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(ingredient.quantity).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                            Text(ingredient.name).font(.system(.title2, design: .rounded, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                        }.fixedSize(horizontal: false, vertical: true) }
                    }
                    Divider()
                    if !step.sectionTitle.isEmpty { Text(step.sectionTitle).font(.system(.title2, design: .serif).weight(.semibold)) }
                    Text(step.originalInstruction).font(.system(.title, design: .serif)).fixedSize(horizontal: false, vertical: true).lineSpacing(5)
                }.padding(.vertical, 8)
            }
            HStack(spacing: 14) {
                Button { moveStep(-1) } label: { Label("Previous", systemImage: "chevron.left").frame(maxWidth: .infinity).padding() }.disabled(stepIndex == 0).buttonStyle(.bordered)
                Button { moveStep(1) } label: { HStack { Text(stepIndex == recipe.steps.indices.last ? "Finish" : "Next"); Image(systemName: "chevron.right") }.frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .background(Color(uiColor: .systemBackground))
        .onAppear { restoreStep(); setAwake(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in setAwake(phase == .active) }
        .onChange(of: stepIndex) { _, _ in persistStep() }
        .onDisappear { setAwake(false) }
        .interactiveDismissDisabled()
    }
    private func setAwake(_ value: Bool) { UIApplication.shared.isIdleTimerDisabled = value }
    private func restoreStep() {
        guard let saved = sessions.first, let index = recipe.steps.firstIndex(where: { $0.id == saved.stepID }) else { return }
        stepIndex = index
    }
    private func openSection(_ section: String) {
        if let saved = sessions.first?.sectionProgress[section], let index = recipe.steps.firstIndex(where: { $0.id == saved }) { stepIndex = index }
        else if let index = recipe.steps.firstIndex(where: { ($0.sectionTitle.isEmpty ? recipe.title : $0.sectionTitle) == section }) { stepIndex = index }
    }
    private func moveStep(_ direction: Int) {
        guard let position = stepsInCurrentSection.firstIndex(of: stepIndex) else { return }
        let nextPosition = position + direction
        if stepsInCurrentSection.indices.contains(nextPosition) { stepIndex = stepsInCurrentSection[nextPosition]; return }
        guard let sectionIndex = sections.firstIndex(of: currentSection) else { return }
        let nextSectionIndex = sectionIndex + direction
        guard sections.indices.contains(nextSectionIndex) else {
            if direction > 0 { clearSession(); dismiss() }
            return
        }
        openSection(sections[nextSectionIndex])
    }
    private func persistStep() {
        guard recipe.steps.indices.contains(stepIndex) else { return }
        if let saved = sessions.first {
            saved.stepID = recipe.steps[stepIndex].id
            var progress = saved.sectionProgress
            progress[currentSection] = recipe.steps[stepIndex].id
            saved.sectionProgressData = (try? JSONEncoder().encode(progress)) ?? saved.sectionProgressData
            saved.updatedAt = .now
        } else {
            let record = CookingSessionRecord(recipeID: recipe.id, stepID: recipe.steps[stepIndex].id)
            record.sectionProgressData = (try? JSONEncoder().encode([currentSection: recipe.steps[stepIndex].id])) ?? Data("{}".utf8)
            modelContext.insert(record)
        }
    }
    private func clearSession() { sessions.forEach { modelContext.delete($0) } }
}

struct GroceryReviewView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("reminderListID") private var selectedListID = ""
    @State private var lists: [EKCalendar] = []
    @State private var existing: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var loading = true
    private let store = EKEventStore()
    private var buyItems: [RecipeIngredient] { uniqueIngredients.filter { !$0.staple } }
    private var staples: [RecipeIngredient] { uniqueIngredients.filter(\.staple) }
    private var uniqueIngredients: [RecipeIngredient] {
        var seen = Set<String>()
        return recipe.ingredients.filter { !$0.excludeFromGroceries && seen.insert(normalize($0.groceryName)).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if loading { ProgressView("Loading Reminders lists…") }
                    else if lists.isEmpty { Text(message ?? "No writable Reminders lists found.").foregroundStyle(.secondary) }
                    else { Picker("Destination list", selection: $selectedListID) {
                        Text("Select a list").tag("")
                        ForEach(lists, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                    }.onChange(of: selectedListID) { _, _ in loadExisting() } }
                } header: { Text("Add to") }
                group("Ingredients to buy", items: buyItems)
                group("Pantry staples", items: staples)
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Review Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add selected") { addSelected() }.disabled(loading || selectedListID.isEmpty || selected.isEmpty) }
            }
            .task { await requestAccess() }
        }
    }

    @ViewBuilder private func group(_ title: String, items: [RecipeIngredient]) -> some View {
        Section {
            HStack(spacing: 12) {
                Button("Select all") { selected.formUnion(items.map(\.id)) }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle()).buttonStyle(.bordered)
                Spacer(minLength: 20)
                Button("Clear") { items.forEach { selected.remove($0.id) } }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle()).buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                let key = normalize(item.groceryName)
                Button { if !existing.contains(key) { selected.formSymmetricDifference([item.id]) } } label: {
                    HStack { Image(systemName: existing.contains(key) ? "checkmark.circle.fill" : (selected.contains(item.id) ? "checkmark.circle.fill" : "circle")); Text(item.groceryName); Spacer(); if existing.contains(key) { Text("Already on list").font(.caption).foregroundStyle(.secondary) } }
                }.disabled(existing.contains(key)).foregroundStyle(existing.contains(key) ? .secondary : .primary)
            }
        } header: { Text(title) }
    }

    @MainActor private func requestAccess() async {
        do {
            if #available(iOS 17.0, *) { try await store.requestFullAccessToReminders() } else { try await store.requestAccess(to: .reminder) }
            lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
            if selectedListID.isEmpty { message = "Choose the Reminders list in Settings before adding groceries." }
            else if !lists.contains(where: { $0.calendarIdentifier == selectedListID }) { message = "The selected Reminders list is unavailable. Choose another list in Settings." }
            loading = false
            loadExisting()
        } catch { message = "Allow Reminders access in Settings to choose a list."; loading = false }
    }

    private func loadExisting() {
        guard let calendar = lists.first(where: { $0.calendarIdentifier == selectedListID }) else { existing = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        store.fetchReminders(matching: predicate) { reminders in
            let keys = Set((reminders ?? []).map { normalize($0.title) })
            DispatchQueue.main.async {
                let hadSelection = !selected.isEmpty
                existing = keys
                if hadSelection { selected.formIntersection(Set(uniqueIngredients.filter { !keys.contains(normalize($0.groceryName)) }.map(\.id))) }
                else { selected = Set(buyItems.filter { !keys.contains(normalize($0.groceryName)) }.map(\.id)) }
            }
        }
    }

    private func addSelected() {
        guard let calendar = lists.first(where: { $0.calendarIdentifier == selectedListID }), calendar.allowsContentModifications else { message = "That list is unavailable or read-only. Choose another list in Settings."; return }
        let items = uniqueIngredients.filter { selected.contains($0.id) && !existing.contains(normalize($0.groceryName)) }
        guard !items.isEmpty else { message = "All selected ingredients are already on this list."; return }
        var savedCount = 0
        var saveFailed = false
        for item in items {
            let reminder = EKReminder(eventStore: store); reminder.calendar = calendar; reminder.title = item.groceryName
            do { try store.save(reminder, commit: false); savedCount += 1 } catch { saveFailed = true }
        }
        do {
            try store.commit()
            guard !saveFailed, savedCount == items.count else {
                message = "Added \(savedCount) of \(items.count) items. Check Reminders before retrying."
                return
            }
            RecipeUsageStore(context: modelContext).recordCompletedGroceryFlow(recipe.id)
            dismiss()
        } catch { message = "Added \(savedCount) of \(items.count) items. Check Reminders before retrying." }
    }

    private func normalize(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
