import SwiftUI
import SwiftData
import PhotosUI
import UIKit

@main struct CookbookApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
        .modelContainer(for: [RecipeNote.self, RecipePhoto.self, DinnerTimeline.self, CookingSessionRecord.self, PlannedDinnerRecipe.self, RecipeUsageStats.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            RecipeBrowserView().tabItem { Label("Recipes", systemImage: "book.closed") }
            DinnerPlannerView().tabItem { Label("Dinner", systemImage: "calendar.badge.clock") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Color(red: 0.32, green: 0.39, blue: 0.27))
    }
}

struct RecipeBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var selectedLabelIDs: Set<String> = []
    @State private var selectedDinnerRecipeID: String?
    private let recipes = CookbookCatalog.bundled.recipes
    private var labelGroups: [RecipeLabelGroup] { (CookbookCatalog.bundled.labelGroups ?? []).sorted { $0.order < $1.order } }
    private var labels: [RecipeLabel] { CookbookCatalog.bundled.labels ?? [] }
    private func allLabels(in group: RecipeLabelGroup) -> [RecipeLabel] {
        labels.filter { $0.groupID == group.id }.sorted { $0.order < $1.order }
    }
    private func labels(in group: RecipeLabelGroup) -> [RecipeLabel] {
        let otherGroupSelections = Set(labels.filter { $0.groupID != group.id && selectedLabelIDs.contains($0.id) }.map(\.id))
        return allLabels(in: group).filter { candidate in
            selectedLabelIDs.contains(candidate.id) || recipes.contains { recipe in
                matchesSearch(recipe) && RecipeLabelFilter.matches(
                    recipe,
                    selectedLabelIDs: otherGroupSelections.union([candidate.id]),
                    groups: labelGroups,
                    labels: labels
                )
            }
        }
    }
    private func toggle(_ label: RecipeLabel) {
        selectedLabelIDs = RecipeLabelFilter.togglingSingle(label, selectedLabelIDs: selectedLabelIDs, labels: labels)
    }
    private func clearLabels(in group: RecipeLabelGroup) {
        selectedLabelIDs.subtract(allLabels(in: group).map(\.id))
    }
    private var hasLabelFilters: Bool { !selectedLabelIDs.isEmpty }
    private func selectionCount(in group: RecipeLabelGroup) -> Int {
        allLabels(in: group).filter { selectedLabelIDs.contains($0.id) }.count
    }
    private var activeFilterCount: Int { selectedLabelIDs.count }
    private func matchesSearch(_ recipe: Recipe) -> Bool {
        query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var visibleCategories: [String] {
        CookbookCatalog.bundled.categoryOrder.filter { sectionName in filtered.contains { $0.category == sectionName } }
    }
    private func browserGroups(in sectionName: String) -> [BrowserGroup] {
        var result: [BrowserGroup] = []
        var regularRecipes: [Recipe] = []
        func flushRegular() {
            guard !regularRecipes.isEmpty else { return }
            result.append(BrowserGroup(id: "\(sectionName)-regular-\(result.count)", title: nil, recipes: regularRecipes))
            regularRecipes = []
        }
        for recipe in filtered where recipe.category == sectionName {
            if let collectionTitle = recipe.collectionTitle {
                flushRegular()
                if let last = result.last, last.title == collectionTitle {
                    result[result.count - 1] = BrowserGroup(id: last.id, title: collectionTitle, recipes: last.recipes + [recipe])
                } else {
                    result.append(BrowserGroup(id: "\(sectionName)-collection-\(result.count)", title: collectionTitle, recipes: [recipe]))
                }
            } else {
                regularRecipes.append(recipe)
            }
        }
        flushRegular()
        return result
    }
    private var filtered: [Recipe] {
        recipes.filter { recipe in
            return matchesSearch(recipe) &&
                RecipeLabelFilter.matches(recipe, selectedLabelIDs: selectedLabelIDs, groups: labelGroups, labels: labels)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            NavigationStack {
                ZStack {
                    VStack(spacing: 0) {
                        browserContent
                    }
                    .opacity(isLandscape ? 0 : 1)
                    .allowsHitTesting(!isLandscape)
                    .accessibilityHidden(isLandscape)

                    DinnerIdeasLayoutView(recipes: filtered, selectedRecipeID: $selectedDinnerRecipeID)
                        .opacity(isLandscape ? 1 : 0)
                        .allowsHitTesting(isLandscape)
                        .accessibilityHidden(!isLandscape)
                }
                .navigationTitle(isLandscape ? "" : "Cookbook")
                .navigationBarTitleDisplayMode(isSearchPresented ? .inline : .large)
                .modifier(PresentedRecipeSearch(query: $query, isPresented: $isSearchPresented))
                .toolbar {
                    if !isLandscape {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if !isSearchPresented {
                                recipeFilterMenu
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { isSearchPresented = true }
                                } label: { Image(systemName: "magnifyingglass") }
                                    .accessibilityLabel("Search recipes")
                            }
                        }
                    }
                }
                .onChange(of: isSearchPresented) { _, isPresented in
                    if !isPresented { query = "" }
                }
            }
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
            .toolbar(isLandscape ? .hidden : .visible, for: .tabBar)
        }
    }

    @ViewBuilder private var browserContent: some View {
        if filtered.isEmpty {
            ContentUnavailableView {
                Label("No matching recipes", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try changing a label or search.")
            } actions: {
                Button("Clear filters") { selectedLabelIDs.removeAll(); query = "" }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(visibleCategories, id: \.self) { sectionName in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(sectionName).font(.system(.title2, design: .serif).weight(.semibold))
                            ForEach(browserGroups(in: sectionName)) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    if let title = group.title { Text(title).font(.headline) }
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                                        ForEach(group.recipes) { recipe in NavigationLink(destination: RecipeDetailView(recipe: recipe)) { RecipeTile(recipe: recipe) }.buttonStyle(.plain).simultaneousGesture(TapGesture().onEnded { RecipeUsageStore(context: modelContext).recordRecipeOpen(recipe.id) }) }
                                    }
                                }
                            }
                        }
                    }
                }.padding()
            }
        }
    }

    private var recipeFilterMenu: some View {
        Menu {
            ForEach(labelGroups) { group in
                Section(group.displayName) {
                    ForEach(labels(in: group)) { label in
                        Button {
                            toggle(label)
                        } label: {
                            if selectedLabelIDs.contains(label.id) {
                                Label(label.displayName, systemImage: "checkmark")
                            } else {
                                Text(label.displayName)
                            }
                        }
                    }
                    if selectionCount(in: group) > 0 {
                        Button("Clear \(group.displayName)") { clearLabels(in: group) }
                    }
                }
            }
            if hasLabelFilters {
                Divider()
                Button("Clear all filters") { selectedLabelIDs.removeAll() }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .overlay(alignment: .topTrailing) {
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 8, y: -7)
                    }
                }
        }
        .accessibilityLabel("Filters")
        .accessibilityValue(activeFilterCount == 0 ? "No active filters" : "\(activeFilterCount) active \(activeFilterCount == 1 ? "filter" : "filters")")
        .accessibilityHint("Opens Protein, Meal Style, and Ingredients filters.")
    }
}

private struct BrowserGroup: Identifiable {
    let id: String
    let title: String?
    let recipes: [Recipe]
}

private struct PresentedRecipeSearch: ViewModifier {
    @Binding var query: String
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if isPresented {
            content.searchable(
                text: $query,
                isPresented: $isPresented,
                placement: .toolbarPrincipal,
                prompt: "Recipes or ingredients"
            )
        } else {
            content
        }
    }
}

struct RecipeTile: View {
    let recipe: Recipe
    @Query private var photos: [RecipePhoto]
    init(recipe: Recipe) {
        self.recipe = recipe
        let recipeID = recipe.id
        _photos = Query(filter: #Predicate<RecipePhoto> { $0.recipeID == recipeID && $0.isCover })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let photo = photos.first, let image = UIImage(contentsOfFile: UserFiles.url(for: photo.relativePath).path) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 122).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            } else if let asset = recipe.thumbnailAsset,
                      let url = Bundle.main.url(forResource: asset, withExtension: nil, subdirectory: "Thumbnails"),
                      let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 122).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                RoundedRectangle(cornerRadius: 13).fill(Color(red: 0.90, green: 0.89, blue: 0.83)).overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.white))
                    .frame(height: 122)
            }
            Text(recipe.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            Text(recipe.category).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecipeArtwork: View {
    let recipe: Recipe
    var height: CGFloat

    var body: some View {
        Group {
            if let asset = recipe.thumbnailAsset,
               let url = Bundle.main.url(forResource: asset, withExtension: nil, subdirectory: "Thumbnails"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(red: 0.89, green: 0.88, blue: 0.82))
                    .overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.white))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityLabel("Photo of \(recipe.title)")
    }
}

private struct DinnerIdeasLayoutView: View {
    let recipes: [Recipe]
    @Binding var selectedRecipeID: String?
    @State private var showDinner = false
    @State private var dinnerWasSaved = false
    @State private var showGroceries = false

    init(recipes: [Recipe], selectedRecipeID: Binding<String?>) {
        self.recipes = recipes
        _selectedRecipeID = selectedRecipeID
    }

    private var index: Int { recipes.firstIndex(where: { $0.id == selectedRecipeID }) ?? 0 }
    private var recipe: Recipe? { recipes.first(where: { $0.id == selectedRecipeID }) ?? recipes.first }
    private var description: String? {
        guard let recipe else { return nil }
        let value = (recipe.menuDescription ?? recipe.introduction)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
                if let recipe {
                    landscapeLayout(size: geometry.size, recipe: recipe)
                } else {
                    ContentUnavailableView {
                        Label("No matching recipes", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Rotate to portrait to change or clear your filters.")
                    }
                }
            }
            .foregroundStyle(Color(red: 0.07, green: 0.12, blue: 0.09))
        }
        .onAppear { reconcileSelection(with: recipes.map(\.id)) }
        .onChange(of: recipes.map(\.id)) { _, newIDs in reconcileSelection(with: newIDs) }
        .sheet(isPresented: $showDinner, onDismiss: {
            if dinnerWasSaved { showGroceries = true; dinnerWasSaved = false }
        }) {
            if let recipe { AddRecipeToDinnerView(recipe: recipe) { dinnerWasSaved = true } }
        }
        .sheet(isPresented: $showGroceries) {
            if let recipe { GroceryReviewView(recipe: recipe) }
        }
    }

    private func reconcileSelection(with recipeIDs: [String]) {
        guard !recipeIDs.contains(selectedRecipeID ?? "") else { return }
        selectedRecipeID = recipeIDs.first
    }

    private func landscapeLayout(size: CGSize, recipe: Recipe) -> some View {
        let compact = size.height < 390
        let verticalPadding: CGFloat = compact ? 2 : 18
        let horizontalPadding: CGFloat = compact ? 14 : 24
        let leadingPadding = horizontalPadding + (compact ? 8 : 12)
        let trailingPadding = horizontalPadding
        let columnSpacing: CGFloat = compact ? 16 : 28
        let panelHeight = max(0, size.height - verticalPadding * 2)
        let contentInset = compact ? CGFloat(10) : 26
        let columnWidth = max(0, (size.width - leadingPadding - trailingPadding - columnSpacing) * (compact ? 0.45 : 0.38))
        return HStack(alignment: .top, spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: compact ? 11 : 20) {
                    Text("\(recipe.category.uppercased())  /  DINNER IDEAS")
                        .font(.system(size: compact ? 8 : 12, weight: .bold)).tracking(compact ? 1 : 2).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.27))
                    Text(recipe.title)
                        .font(.system(size: min(compact ? 24 : 44, size.height * (compact ? 0.07 : 0.09)), weight: .semibold, design: .serif))
                        .lineLimit(compact ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description {
                        Text(description)
                            .font(.system(size: compact ? 13 : 18))
                            .lineSpacing(compact ? 0 : 5)
                            .lineLimit(compact ? 4 : nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.primary.opacity(0.82))
                    }
                    landscapePairingSection(compact: compact, recipe: recipe)
                }
                Spacer(minLength: compact ? 8 : 16)
                eatButton(compact: compact)
            }
            .padding(.vertical, contentInset)
            .frame(width: columnWidth, height: panelHeight, alignment: .topLeading)
            RecipeArtwork(recipe: recipe, height: panelHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(alignment: .leading) { pageArrow(previous: true).padding(.leading, 12) }
                .overlay(alignment: .trailing) { pageArrow(previous: false).padding(.trailing, 12) }
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            DragGesture(minimumDistance: 35).onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }
                move(by: horizontal < 0 ? 1 : -1)
            }
        )
    }

    private func eatButton(compact: Bool) -> some View {
        Button { showDinner = true } label: {
            Text("LET’S EAT").font(.system(size: compact ? 14 : 17, weight: .bold)).tracking(compact ? 1.6 : 3)
                .frame(maxWidth: .infinity, minHeight: compact ? 40 : 58)
                .background(Color(red: 0.12, green: 0.27, blue: 0.16), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func landscapePairingSection(compact: Bool, recipe: Recipe) -> some View {
        let pairings = recipe.menuPairings ?? ["A crisp green salad", "Seasonal vegetables"]
        return VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Rectangle().fill(Color.primary.opacity(0.16)).frame(height: 1)
            Text("SERVE IT WITH").font(.system(size: compact ? 9 : 12, weight: .bold)).tracking(compact ? 1.2 : 2).foregroundStyle(Color(red: 0.25, green: 0.34, blue: 0.24))
            Text(pairings.joined(separator: "  ·  "))
                .font(.system(size: compact ? 12 : 17))
                .lineLimit(compact ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func pageArrow(previous: Bool) -> some View {
        Button { move(by: previous ? -1 : 1) } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right")
                .font(.title2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 48, height: 54).background(Color.black.opacity(0.58), in: Capsule())
        }
        .disabled(recipes.count < 2 || (previous ? index == 0 : index >= recipes.count - 1))
        .opacity(recipes.count < 2 || (previous ? index == 0 : index >= recipes.count - 1) ? 0.35 : 1)
        .accessibilityLabel(previous ? "Previous recipe" : "Next recipe")
    }

    private func move(by offset: Int) {
        let target = min(max(index + offset, 0), recipes.count - 1)
        guard recipes.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedRecipeID = recipes[target].id }
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var showGroceries = false
    @State private var showNote = false
    @State private var showCamera = false
    @State private var showPrint = false
    @State private var showNoteEdit = false
    @State private var showCooking = false
    @State private var showAddToDinner = false
    @State private var noteToEdit: RecipeNote?
    @State private var pickedPhoto: PhotosPickerItem?
    @Environment(\.modelContext) private var modelContext
    @Query private var photos: [RecipePhoto]
    @Query private var notes: [RecipeNote]
    init(recipe: Recipe) {
        self.recipe = recipe
        let recipeID = recipe.id
        _photos = Query(filter: #Predicate<RecipePhoto> { $0.recipeID == recipeID })
        _notes = Query(filter: #Predicate<RecipeNote> { $0.recipeID == recipeID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(recipe.title).font(.system(size: 34, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
                if !recipe.introduction.isEmpty { Text(recipe.introduction).font(.body).foregroundStyle(.secondary) }
                if let cover = photos.first(where: \.isCover), let image = UIImage(contentsOfFile: UserFiles.url(for: cover.relativePath).path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(maxHeight: 260).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                }
                SectionTitle("Ingredients")
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(recipe.ingredients) { ingredient in HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(ingredient.quantity).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                        Text(ingredient.name).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.body).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true) }
                }
                SectionTitle("Instructions")
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { number, step in
                    VStack(alignment: .leading, spacing: 7) {
                        if !step.sectionTitle.isEmpty && (number == 0 || recipe.steps[number - 1].sectionTitle != step.sectionTitle) {
                            Text(step.sectionTitle).font(.headline).padding(.top, 10)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(number + 1)").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 3)
                            Text(step.originalInstruction).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                ForEach(recipe.tips, id: \.self) { Text("Tip: \($0)").italic().foregroundStyle(.secondary) }
                ForEach(recipe.healthierOptions, id: \.self) { Text("Healthier option: \($0)").italic().foregroundStyle(.secondary) }
                SectionTitle("My notes")
                if activeNotes.isEmpty { Text("No notes yet.").foregroundStyle(.secondary) }
                ForEach(activeNotes) { note in
                    Button { noteToEdit = note; showNoteEdit = true } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.text).font(.body).multilineTextAlignment(.leading)
                            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.foregroundStyle(.primary).contextMenu { Button("Delete Note", role: .destructive) { note.deletedAt = .now; note.updatedAt = .now } }
                }
                Button { showCooking = true } label: { Label("Start cooking", systemImage: "play.fill").frame(maxWidth: .infinity).padding(14).background(.primary, in: Capsule()).foregroundStyle(.background) }
            }.padding(22)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCooking = true } label: { Label("Start Cooking", systemImage: "play.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showGroceries = true } label: { Label("Add to Groceries…", systemImage: "cart") }
                Button { showAddToDinner = true } label: { Label("Add to Dinner…", systemImage: "calendar.badge.plus") }
                Button { showCooking = true } label: { Label("Start Cooking", systemImage: "play.fill") }
                Button { showNote = true } label: { Label("Add Note", systemImage: "note.text") }
                PhotosPicker(selection: $pickedPhoto, matching: .images) { Label("Add Photo", systemImage: "camera") }
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera.fill") }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                Button { showPrint = true } label: { Label("Print Recipe", systemImage: "printer") }
            } label: { Image(systemName: "ellipsis.circle") }
        }}
        .sheet(isPresented: $showGroceries) { GroceryReviewView(recipe: recipe) }
        .sheet(isPresented: $showCooking) { CookingModeView(recipe: recipe) }
        .sheet(isPresented: $showAddToDinner) { AddRecipeToDinnerView(recipe: recipe) }
        .sheet(isPresented: $showNote) { NoteEditorView(recipe: recipe) }
        .sheet(isPresented: $showNoteEdit) { if let noteToEdit { NoteEditorView(recipe: recipe, note: noteToEdit) } }
        .sheet(isPresented: $showPrint) { RecipePrintView(recipe: recipe) }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in savePhoto(image) }
        }
        .onChange(of: pickedPhoto) { _, item in Task { await savePhoto(item) } }
    }

    private var activeNotes: [RecipeNote] { notes.filter { $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt } }

    @MainActor private func savePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        savePhoto(image)
        pickedPhoto = nil
    }

    @MainActor private func savePhoto(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.88) else { return }
        let name = "\(UUID().uuidString).jpg"
        do { try jpeg.write(to: UserFiles.url(for: name), options: .atomic); photos.forEach { $0.isCover = false }; modelContext.insert(RecipePhoto(recipeID: recipe.id, relativePath: name, isCover: true)) } catch { }
    }
}

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.system(.title2, design: .serif).weight(.semibold)).padding(.top, 8) }
}

struct AddRecipeToDinnerView: View {
    let recipe: Recipe
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var scheduled: [PlannedDinnerRecipe]
    @State private var dinnerDate = Calendar.current.date(byAdding: .day, value: 1, to: .now).flatMap { Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: $0) } ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Dinner date") {
                    DatePicker("Serve at", selection: $dinnerDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Text("This recipe will appear under its date in Dinner. Add other recipes to the same date, then generate a plan from that dinner.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add to Dinner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { save() } }
            }
        }
    }

    private func save() {
        if let existing = scheduled.first(where: { $0.recipeID == recipe.id && Calendar.current.isDate($0.dinnerDate, inSameDayAs: dinnerDate) }) {
            existing.dinnerDate = dinnerDate
        } else {
            context.insert(PlannedDinnerRecipe(recipeID: recipe.id, dinnerDate: dinnerDate))
        }
        onSaved()
        dismiss()
    }
}

