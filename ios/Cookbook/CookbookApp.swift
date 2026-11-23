import SwiftUI
import SwiftData
import PhotosUI
import UIKit

@main struct CookbookApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
        .modelContainer(for: [RecipeNote.self, RecipePhoto.self, DinnerTimeline.self, CookingSessionRecord.self, PlannedDinnerRecipe.self, RecipeDinnerUsage.self, RecipeUsageStats.self, FamilyMember.self, DinnerVote.self, RecipeDinnerVote.self, ImportedPaprikaRecipe.self, ImportedWebRecipe.self, ImportedMagazineRecipe.self, PaprikaImportRun.self, DeletedRecipe.self, ImageGenerationRun.self, ImageGenerationEntry.self, RecipeCategory.self, RecipeCategorySettings.self, RecipeCategoryAssignment.self])
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var incomingPaprikaURL: URL?
    @State private var categorySetupError: String?
    @State private var dinnerUsageSetupError: String?
    @State private var familySetupError: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            RecipeBrowserView().tabItem { Label("Recipes", systemImage: "book.closed") }.tag(0)
            DinnerPlannerView().tabItem { Label("Dinner", systemImage: "calendar.badge.clock") }.tag(1)
            SettingsView(incomingPaprikaURL: $incomingPaprikaURL).tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .tint(Color(red: 0.32, green: 0.39, blue: 0.27))
        .onOpenURL { url in
            incomingPaprikaURL = url
            selectedTab = 2
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == 2 { openPendingPaprikaShareIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { openPendingPaprikaShareIfNeeded() }
        }
        .task {
            do {
                _ = try FamilyDinnerStore.mergeDuplicateMembers(in: modelContext)
                try FamilyDinnerStore.initializeRequestedFamilyRosterIfNeeded(in: modelContext)
            } catch { familySetupError = "Could not update family members: \(error.localizedDescription)" }
            do { _ = try RecipeDinnerUsageStore.backfillMissingEvents(in: modelContext) }
            catch { dinnerUsageSetupError = "Could not restore planned dinner history: \(error.localizedDescription)" }
            do { try RecipeCategoryStore.seedIfNeeded(in: modelContext) }
            catch { categorySetupError = "Could not initialize recipe categories: \(error.localizedDescription)" }
            openPendingPaprikaShareIfNeeded()
        }
        .alert("Dinner history", isPresented: Binding(get: { dinnerUsageSetupError != nil }, set: { if !$0 { dinnerUsageSetupError = nil } })) {
            Button("OK") { dinnerUsageSetupError = nil }
        } message: { Text(dinnerUsageSetupError ?? "") }
        .alert("Recipe categories", isPresented: Binding(get: { categorySetupError != nil }, set: { if !$0 { categorySetupError = nil } })) {
            Button("OK") { categorySetupError = nil }
        } message: { Text(categorySetupError ?? "") }
        .alert("Family members", isPresented: Binding(get: { familySetupError != nil }, set: { if !$0 { familySetupError = nil } })) {
            Button("OK") { familySetupError = nil }
        } message: { Text(familySetupError ?? "") }
    }

    private func openPendingPaprikaShareIfNeeded() {
        guard incomingPaprikaURL == nil, let url = PaprikaShareInbox.nextPendingURL() else { return }
        incomingPaprikaURL = url
        selectedTab = 2
    }
}

struct RecipeBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var importedWebRecords: [ImportedWebRecipe]
    @Query private var importedMagazineRecords: [ImportedMagazineRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @Query(sort: \RecipeCategory.order) private var categories: [RecipeCategory]
    @Query private var categorySettings: [RecipeCategorySettings]
    @Query private var categoryAssignments: [RecipeCategoryAssignment]
    @Query private var dinnerUsages: [RecipeDinnerUsage]
    @Query private var recipeDinnerVotes: [RecipeDinnerVote]
    private let importRunLabelID: String?
    private let showingDeletedRecipes: Bool
    private let managesNavigationStack: Bool
    private let screenTitle: String?
    private let imageRunID: UUID?
    @State private var query = ""
    @State private var isSearchPresented = false
    @State private var selectedLabelIDs: Set<String> = []
    @State private var showingFavorites = false
    @State private var selectedDinnerRecipeID: String?
    @Query private var imageGenerationEntries: [ImageGenerationEntry]
    init(importRunLabelID: String? = nil, showingDeletedRecipes: Bool = false, managesNavigationStack: Bool = true, screenTitle: String? = nil, imageRunID: UUID? = nil) {
        self.importRunLabelID = importRunLabelID
        self.showingDeletedRecipes = showingDeletedRecipes
        self.managesNavigationStack = managesNavigationStack
        self.screenTitle = screenTitle
        self.imageRunID = imageRunID
    }

    private var availableImportedRecords: [ImportedPaprikaRecipe] {
        importedRecords.filter { showingDeletedRecipes ? $0.deletedAt != nil : $0.deletedAt == nil }
    }
    private var recipes: [Recipe] {
        let importedRecipes = availableImportedRecords.compactMap(\.recipe) + importedWebRecords.filter { showingDeletedRecipes ? $0.deletedAt != nil : $0.deletedAt == nil }.compactMap(\.recipe) + importedMagazineRecords.filter { showingDeletedRecipes ? $0.deletedAt != nil : $0.deletedAt == nil }.compactMap(\.recipe)
        let deletedIDs = Set(deletedRecipes.map(\.recipeID))
        let deletedBundledRecipes = CookbookCatalog.bundled.recipes.filter { deletedIDs.contains($0.id) }
        if showingDeletedRecipes { return importedRecipes + deletedBundledRecipes }
        return CookbookCatalog.bundled.recipes.filter { !deletedIDs.contains($0.id) } + importedRecipes
    }
    private var defaultCategoryID: String { categorySettings.first?.defaultCategoryID ?? categories.first?.id ?? RecipeCategoryStore.fallbackID }
    private var categoryOrder: [String] { categories.sorted { $0.order < $1.order }.map(\.id) }
    private func categoryID(for recipe: Recipe) -> String {
        if let assignment = categoryAssignments.first(where: { $0.recipeID == recipe.id }), categories.contains(where: { $0.id == assignment.categoryID }) {
            return assignment.categoryID
        }
        return RecipeCategoryStore.match(sourceNames: [recipe.category], categories: categories)?.id ?? defaultCategoryID
    }
    private func categoryName(for id: String) -> String { categories.first(where: { $0.id == id })?.name ?? "General" }
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
    private var activeFilterCount: Int { selectedLabelIDs.count + (showingFavorites ? 1 : 0) }
    private func matchesSearch(_ recipe: Recipe) -> Bool {
        query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var familyRatingsByRecipeID: [String: Double] {
        let today = Calendar.current.startOfDay(for: .now)
        let recipeIDByUsageID = Dictionary(
            dinnerUsages
                .filter { Calendar.current.startOfDay(for: $0.dinnerDate) <= today }
                .map { ($0.id, $0.recipeID) },
            uniquingKeysWith: { first, _ in first }
        )
        var totals: [String: (sum: Double, count: Int)] = [:]
        for vote in recipeDinnerVotes where (0.5...5).contains(vote.stars) {
            guard let recipeID = recipeIDByUsageID[vote.recipeDinnerUsageID] else { continue }
            var total = totals[recipeID] ?? (sum: 0, count: 0)
            total.sum += vote.stars
            total.count += 1
            totals[recipeID] = total
        }
        return totals.mapValues { $0.sum / Double($0.count) }
    }
    private var visibleCategories: [String] {
        categoryOrder.filter { categoryKey in filtered.contains { categoryID(for: $0) == categoryKey } }
    }
    private func browserGroups(in sectionName: String) -> [BrowserGroup] {
        var result: [BrowserGroup] = []
        var regularRecipes: [Recipe] = []
        func flushRegular() {
            guard !regularRecipes.isEmpty else { return }
            result.append(BrowserGroup(id: "\(sectionName)-regular-\(result.count)", title: nil, recipes: regularRecipes))
            regularRecipes = []
        }
        for recipe in filtered where categoryID(for: recipe) == sectionName {
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
        let matchingRecipes = recipes.filter { recipe in
            return matchesSearch(recipe) &&
                (imageRunID.map { runID in imageGenerationEntries.contains { $0.runID == runID && $0.recipeID == recipe.id && $0.generatedPhotoID != nil } } ?? true) &&
                (importRunLabelID.map { recipe.browseLabelIDs.contains($0) } ?? true) &&
                RecipeLabelFilter.matches(recipe, selectedLabelIDs: selectedLabelIDs, groups: labelGroups, labels: labels)
        }
        guard showingFavorites else { return matchingRecipes }
        let ratingsByRecipe = familyRatingsByRecipeID
        return matchingRecipes
            .filter { (ratingsByRecipe[$0.id] ?? 0) >= 2 }
            .sorted {
                let leftRating = ratingsByRecipe[$0.id] ?? 0
                let rightRating = ratingsByRecipe[$1.id] ?? 0
                if leftRating != rightRating { return leftRating > rightRating }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            Group {
                if managesNavigationStack {
                    NavigationStack { browserNavigationContent(isLandscape: isLandscape) }
                } else {
                    browserNavigationContent(isLandscape: isLandscape)
                }
            }
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
        }
    }

    private func browserNavigationContent(isLandscape: Bool) -> some View {
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
        .navigationTitle(isLandscape ? "" : (screenTitle ?? (showingDeletedRecipes ? "Deleted Recipes" : "Cookbook")))
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

    @ViewBuilder private var browserContent: some View {
        if filtered.isEmpty {
            ContentUnavailableView {
                Label("No matching recipes", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try changing your filters or search.")
            } actions: {
                Button("Clear filters") { selectedLabelIDs.removeAll(); showingFavorites = false; query = "" }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            if showingFavorites {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe)) { RecipeTile(recipe: recipe) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(visibleCategories, id: \.self) { sectionName in
                            VStack(alignment: .leading, spacing: 16) {
                                categoryJumpMenu(sectionName: sectionName, scrollProxy: proxy)
                                ForEach(browserGroups(in: sectionName)) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        if let title = group.title { Text(title).font(.headline) }
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                                            ForEach(group.recipes) { recipe in NavigationLink(destination: RecipeDetailView(recipe: recipe)) { RecipeTile(recipe: recipe) }.buttonStyle(.plain) }
                                        }
                                    }
                                }
                            }
                            .id(sectionName)
                        }
                    }.padding()
                }
            }
            }
        }
    }

    private func categoryJumpMenu(sectionName: String, scrollProxy: ScrollViewProxy) -> some View {
        return Menu {
            ForEach(visibleCategories, id: \.self) { targetSectionID in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo(targetSectionID, anchor: .top)
                    }
                } label: {
                    if targetSectionID == sectionName {
                        Label(categoryName(for: targetSectionID), systemImage: "checkmark")
                    } else {
                        Text(categoryName(for: targetSectionID))
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(categoryName(for: sectionName))
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jump to category")
        .accessibilityValue(categoryName(for: sectionName))
        .accessibilityHint("Opens the recipe categories and jumps to the selected section.")
    }

    private var recipeFilterMenu: some View {
        Menu {
            Button {
                showingFavorites.toggle()
            } label: {
                if showingFavorites {
                    Label("Favorites", systemImage: "checkmark")
                } else {
                    Text("Favorites")
                }
            }
            Divider()
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
            if hasLabelFilters || showingFavorites {
                Divider()
                Button("Clear all filters") { selectedLabelIDs.removeAll(); showingFavorites = false }
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
        .accessibilityHint("Opens Favorites and recipe label filters.")
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
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecipeArtwork: View {
    let recipe: Recipe
    var height: CGFloat
    @Query private var photos: [RecipePhoto]

    init(recipe: Recipe, height: CGFloat) {
        self.recipe = recipe
        self.height = height
        let recipeID = recipe.id
        _photos = Query(filter: #Predicate<RecipePhoto> { $0.recipeID == recipeID && $0.isCover })
    }

    var body: some View {
        Group {
            if let photo = photos.first, let image = UIImage(contentsOfFile: UserFiles.url(for: photo.relativePath).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let asset = recipe.thumbnailAsset,
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
    private let previewOnly: Bool
    private let previewImage: UIImage?
    @State private var showGroceries = false
    @State private var showNote = false
    @State private var showCamera = false
    @State private var showPrint = false
    @State private var showCooking = false
    @State private var showAddToDinner = false
    @State private var showImageGeneration = false
    @State private var imageEditButtonVisible = false
    @State private var showPhotoPicker = false
    @State private var showDeleteConfirmation = false
    @State private var noteToEdit: RecipeNote?
    @State private var noteCopied = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var paprikaExportURL: URL?
    @State private var showPaprikaShare = false
    @State private var paprikaExportStatus: String?
    @State private var restorationMessage: String?
    @State private var photoStatus: String?
    @State private var exportingPaprika = false
    @State private var recipeDocumentURL: URL?
    @State private var recipeDocumentStatus: String?
    @State private var exportingRecipeDocument = false
    @State private var showRecipeDocumentShare = false
    @State private var recordedRecipeOpen = false
    @Environment(\.modelContext) private var modelContext
    @Query private var photos: [RecipePhoto]
    @Query private var notes: [RecipeNote]
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query private var importedWebRecords: [ImportedWebRecipe]
    @Query private var importedMagazineRecords: [ImportedMagazineRecipe]
    @Query private var deletedRecipes: [DeletedRecipe]
    @Query(sort: \RecipeCategory.order) private var categories: [RecipeCategory]
    @Query private var categoryAssignments: [RecipeCategoryAssignment]
    @Query private var dinnerUsages: [RecipeDinnerUsage]
    @Query private var recipeDinnerVotes: [RecipeDinnerVote]
    init(recipe: Recipe, previewOnly: Bool = false, previewImage: UIImage? = nil) {
        self.recipe = recipe
        self.previewOnly = previewOnly
        self.previewImage = previewImage
        let recipeID = recipe.id
        _photos = Query(filter: #Predicate<RecipePhoto> { $0.recipeID == recipeID })
        _notes = Query(filter: #Predicate<RecipeNote> { $0.recipeID == recipeID })
        _dinnerUsages = Query(filter: #Predicate<RecipeDinnerUsage> { $0.recipeID == recipeID }, sort: \RecipeDinnerUsage.addedAt)
    }

    private var pastDinnerUsages: [RecipeDinnerUsage] {
        let today = Calendar.current.startOfDay(for: .now)
        return dinnerUsages.filter { $0.dinnerDate < today }
    }
    private var recipeRatingVotes: [RecipeDinnerVote] {
        let today = Calendar.current.startOfDay(for: .now)
        let usageIDs = Set(dinnerUsages
            .filter { Calendar.current.startOfDay(for: $0.dinnerDate) <= today }
            .map(\.id))
        return recipeDinnerVotes.filter { usageIDs.contains($0.recipeDinnerUsageID) && (0.5...5).contains($0.stars) }
    }
    private var recipeRating: Double? {
        guard !recipeRatingVotes.isEmpty else { return nil }
        return Double(recipeRatingVotes.reduce(0) { $0 + $1.stars }) / Double(recipeRatingVotes.count)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let previewImage {
                    Image(uiImage: previewImage).resizable().scaledToFill().frame(maxHeight: 260).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                } else if hasEffectiveImage && !previewOnly && !isDeleted {
                    Button {
                        imageEditButtonVisible = true
                    } label: {
                        RecipeArtwork(recipe: recipe, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recipe image")
                    .accessibilityHint("Show image editing options.")
                    .popover(isPresented: $imageEditButtonVisible, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        Menu { imageEditActions } label: {
                            Label("Edit Image", systemImage: "pencil")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(12)
                        .presentationCompactAdaptation(.popover)
                    }
                } else if hasEffectiveImage {
                    RecipeArtwork(recipe: recipe, height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if !previewOnly && !isDeleted {
                    Menu { imageEditActions } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 34))
                            Text("Add Image").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add recipe image")
                }
                Text(recipe.title).font(.system(size: 34, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
                if !recipe.introduction.isEmpty { Text(recipe.introduction).font(.body).foregroundStyle(.secondary) }
                if let servings = recipe.servings, !servings.isEmpty { LabeledContent("Servings", value: servings) }
                ForEach(recipe.orderedContent) { content in
                    if let group = content.group {
                        VStack(alignment: .leading, spacing: 3) {
                            if let title = group.title, !title.isEmpty {
                                Text(title).font(.headline).padding(.bottom, 3)
                            } else if content.id != recipe.orderedContent.first?.id {
                                Divider().padding(.vertical, 4)
                            }
                            ForEach(content.ingredients) { ingredient in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(ingredient.quantity)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.32, green: 0.39, blue: 0.27))
                                        .frame(width: quantityColumnWidth, alignment: .trailing)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(ingredient.name).frame(maxWidth: .infinity, alignment: .leading)
                                }.font(.body).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 2)
                    } else if let step = content.step, let number = content.stepNumber {
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
                }
                ForEach(recipe.tips, id: \.self) { Text("Tip: \($0)").italic().foregroundStyle(.secondary) }
                ForEach(recipe.healthierOptions, id: \.self) { Text("Healthier option: \($0)").italic().foregroundStyle(.secondary) }
                if !previewOnly {
                    HStack(alignment: .center) {
                        SectionTitle("My notes")
                        Spacer()
                        Button { showNote = true } label: { Image(systemName: "plus.circle.fill") }
                            .font(.title3)
                            .accessibilityLabel("Add Note")
                            .accessibilityHint("Add a note to this recipe.")
                    }
                    if activeNotes.isEmpty { Text("No notes yet.").foregroundStyle(.secondary) }
                    ForEach(activeNotes) { note in
                        Button { noteToEdit = note } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.text).font(.body).multilineTextAlignment(.leading)
                                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.primary)
                        .contextMenu {
                            Button { copyNote(note) } label: { Label("Copy Note", systemImage: "doc.on.doc") }
                            Button("Delete Note", role: .destructive) { note.deletedAt = .now; note.updatedAt = .now }
                        }
                    }
                    SectionTitle("Previous Dinners")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pastDinnerUsages.isEmpty ? "No previous dinners yet" : "Added to dinner \(pastDinnerUsages.count) times")
                            .font(.subheadline.weight(.medium))
                        if let latestAddition = pastDinnerUsages.max(by: { $0.addedAt < $1.addedAt }) {
                            Text("Last added \(latestAddition.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    SectionTitle("Family Rating")
                    if let recipeRating {
                        Label("\(recipeRating.formatted(.number.precision(.fractionLength(0...1)))) / 5 · \(recipeRatingVotes.count) \(recipeRatingVotes.count == 1 ? "vote" : "votes")", systemImage: "star.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not rated yet").foregroundStyle(.secondary)
                    }
                }
                if let provenance = recipe.provenance, provenance.type != .paprikaImport {
                    HStack(spacing: 0) {
                        Text(provenance.tagLabel)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recipe source: \(provenance.tagLabel)")
                }
                if !previewOnly {
                    if !isDeleted && !categories.isEmpty {
                        Menu {
                            ForEach(categories.sorted { $0.order < $1.order }) { category in
                                Button {
                                    do { try RecipeCategoryStore.setAssignment(recipeID: recipe.id, categoryID: category.id, in: modelContext) }
                                    catch { restorationMessage = error.localizedDescription }
                                } label: {
                                    if assignedCategoryID == category.id { Label(category.name, systemImage: "checkmark") }
                                    else { Text(category.name) }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text(assignedCategoryName)
                                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(red: 0.32, green: 0.39, blue: 0.27))
                        }
                        .accessibilityLabel("Category: \(assignedCategoryName)")
                        .accessibilityHint("Choose a recipe category.")
                    } else {
                        Label(assignedCategoryName, systemImage: "folder")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }
                if !previewOnly && isDeleted {
                    Button { restoreDeletedRecipe() } label: {
                        Label("Restore Recipe", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 10)
                } else if !previewOnly {
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Label("Delete Recipe", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 10)
                }
            }.padding(22)
        }
        .overlay(alignment: .bottom) {
            if noteCopied {
                Label("Note copied", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .accessibilityAddTraits(.isStaticText)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if !previewOnly && !recordedRecipeOpen {
                recordedRecipeOpen = true
                RecipeUsageStore(context: modelContext).recordRecipeOpen(recipe.id)
            }
        }
        .toolbar {
            if !previewOnly {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showCooking = true } label: { Image(systemName: "play.fill") }
                        .accessibilityLabel("Start Cooking")

                    Menu {
                        Button { showGroceries = true } label: { Label("Add to Groceries…", systemImage: "cart") }
                        Button { showAddToDinner = true } label: { Label("Add to Dinner…", systemImage: "calendar.badge.plus") }
                    } label: {
                        Label("Plan", systemImage: "calendar.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Plan")

                    Menu {
                        Button { showPrint = true } label: { Label("Print Recipe", systemImage: "printer") }
                        Menu {
                            Button { Task { await exportRecipeDocument(format: .markdown) } } label: { Label("Markdown…", systemImage: "doc.text") }.disabled(exportingRecipeDocument)
                            Button { Task { await exportRecipeDocument(format: .html) } } label: { Label("HTML…", systemImage: "chevron.left.forwardslash.chevron.right") }.disabled(exportingRecipeDocument)
                            Button { Task { await exportPaprikaRecipe() } } label: { Label("Paprika File…", systemImage: "square.and.arrow.up") }.disabled(exportingPaprika)
                        } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Share")
                }
            }
        }
        .sheet(isPresented: $showGroceries) { GroceryReviewView(recipe: recipe) }
        .sheet(isPresented: $showImageGeneration) {
            NavigationStack { RecipeImageGenerationView(recipes: [recipe], resumeRun: nil) }
        }
        .sheet(isPresented: $showCooking) { CookingModeView(recipe: recipe) }
        .sheet(isPresented: $showAddToDinner) { AddRecipeToDinnerView(recipe: recipe) }
        .sheet(isPresented: $showNote) { NoteEditorView(recipe: recipe) }
        .sheet(item: $noteToEdit) { note in NoteEditorView(recipe: recipe, note: note) }
        .sheet(isPresented: $showPrint) { RecipePrintView(recipe: recipe) }
        .sheet(isPresented: $showPaprikaShare) {
            if let paprikaExportURL { ActivityView(items: [paprikaExportURL]) }
        }
        .sheet(isPresented: $showRecipeDocumentShare) {
            if let recipeDocumentURL { ActivityView(items: [recipeDocumentURL]) }
        }
        .alert("Recipe export", isPresented: Binding(get: { recipeDocumentStatus != nil }, set: { if !$0 { recipeDocumentStatus = nil } })) {
            Button("OK") { recipeDocumentStatus = nil }
        } message: { Text(recipeDocumentStatus ?? "") }
        .alert("Paprika export", isPresented: Binding(get: { paprikaExportStatus != nil }, set: { if !$0 { paprikaExportStatus = nil } })) {
            Button("OK") { paprikaExportStatus = nil }
        } message: { Text(paprikaExportStatus ?? "") }
        .alert("Recipe update", isPresented: Binding(get: { restorationMessage != nil }, set: { if !$0 { restorationMessage = nil } })) {
            Button("OK") { restorationMessage = nil }
        } message: { Text(restorationMessage ?? "") }
        .alert("Recipe image", isPresented: Binding(get: { photoStatus != nil }, set: { if !$0 { photoStatus = nil } })) {
            Button("OK") { photoStatus = nil }
        } message: { Text(photoStatus ?? "") }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in savePhoto(image) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .confirmationDialog("Delete \(recipe.title)?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive) { deleteRecipe() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This recipe will move to Deleted Recipes in Settings, where you can restore it.")
        }
        .onChange(of: pickedPhoto) { _, item in Task { await savePhoto(item) } }
    }

    @ViewBuilder
    private var imageEditActions: some View {
        Button { Task { await presentPhotoPicker() } } label: { Label("Add Photo", systemImage: "photo") }
        Button { Task { await presentCamera() } } label: { Label("Take Photo", systemImage: "camera.fill") }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
        if !isDeleted {
            Button { Task { await presentImageManagement() } } label: {
                Label(hasEffectiveImage ? "Manage Recipe Images" : "Generate Recipe Cover", systemImage: "sparkles")
            }
        }
    }

    private var activeNotes: [RecipeNote] { notes.filter { $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt } }
    private func copyNote(_ note: RecipeNote) {
        UIPasteboard.general.string = note.text
        withAnimation { noteCopied = true }
        UIAccessibility.post(notification: .announcement, argument: "Note copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { noteCopied = false }
        }
    }
    private var quantityColumnWidth: CGFloat {
        let longest = recipe.ingredients.map { $0.quantity.count }.max() ?? 0
        return min(160, max(76, CGFloat(longest) * 6.2))
    }
    private var assignedCategoryID: String {
        categoryAssignments.first(where: { assignment in assignment.recipeID == recipe.id && categories.contains(where: { $0.id == assignment.categoryID }) })?.categoryID
            ?? RecipeCategoryStore.match(sourceNames: [recipe.category], categories: categories)?.id
            ?? categories.sorted { $0.order < $1.order }.first?.id
            ?? RecipeCategoryStore.fallbackID
    }
    private var assignedCategoryName: String { categories.first(where: { $0.id == assignedCategoryID })?.name ?? recipe.category }
    private var hasEffectiveImage: Bool {
        if photos.contains(where: { $0.recipeID == recipe.id && $0.isCover }) { return true }
        guard let asset = recipe.thumbnailAsset else { return false }
        return Bundle.main.url(forResource: asset, withExtension: nil, subdirectory: "Thumbnails") != nil
    }
    private var deletedImportedRecord: ImportedPaprikaRecipe? { importedRecords.first { $0.id == recipe.id && $0.deletedAt != nil } }
    private var webRecipeRecord: ImportedWebRecipe? { importedWebRecords.first { $0.id == recipe.id } }
    private var deletedRecipeRecord: DeletedRecipe? { deletedRecipes.first { $0.recipeID == recipe.id } }
    private var magazineRecipeRecord: ImportedMagazineRecipe? { importedMagazineRecords.first { $0.id == recipe.id } }
    private var isDeleted: Bool { deletedImportedRecord != nil || deletedRecipeRecord != nil || webRecipeRecord?.deletedAt != nil || magazineRecipeRecord?.deletedAt != nil }

    @MainActor private func deleteRecipe() {
        do {
            if let magazineRecipeRecord {
                magazineRecipeRecord.deletedAt = .now
            } else if let webRecipeRecord {
                webRecipeRecord.deletedAt = .now
            } else if let imported = importedRecords.first(where: { $0.id == recipe.id }) {
                imported.deletedAt = .now
            } else if deletedRecipeRecord == nil {
                modelContext.insert(DeletedRecipe(recipeID: recipe.id))
            }
            try modelContext.save()
            restorationMessage = "\(recipe.title) was moved to Deleted recipes."
        } catch {
            restorationMessage = "Could not delete \(recipe.title): \(error.localizedDescription)"
        }
    }

    @MainActor private func restoreDeletedRecipe() {
        do {
            deletedImportedRecord?.deletedAt = nil
            webRecipeRecord?.deletedAt = nil
            magazineRecipeRecord?.deletedAt = nil
            if let deletedRecipeRecord { modelContext.delete(deletedRecipeRecord) }
            try modelContext.save()
            restorationMessage = "\(recipe.title) was restored to your recipe list."
        } catch {
            restorationMessage = "Could not restore \(recipe.title): \(error.localizedDescription)"
        }
    }

    @MainActor private func exportPaprikaRecipe() async {
        exportingPaprika = true
        defer { exportingPaprika = false }
        do {
            let item = try PaprikaExporter.item(for: recipe, importedRecords: importedRecords, photos: photos)
            let url = PaprikaExporter.temporaryURL(extension: "paprikarecipe")
            try await Task.detached(priority: .userInitiated) { try PaprikaExporter.writeRecipe(item, to: url) }.value
            paprikaExportURL = url
            // Let the ellipsis menu finish dismissing before presenting another controller.
            try await Task.sleep(nanoseconds: 300_000_000)
            showPaprikaShare = true
        } catch { paprikaExportStatus = "Could not export \(recipe.title): \(error.localizedDescription)" }
    }

    private enum RecipeDocumentFormat: Equatable, Sendable {
        case markdown
        case html
    }

    @MainActor private func exportRecipeDocument(format: RecipeDocumentFormat) async {
        exportingRecipeDocument = true
        recipeDocumentURL = nil
        defer { exportingRecipeDocument = false }
        let fileExtension = format == .markdown ? "md" : "html"
        let exportRecipe = recipe
        let url = RecipeDocumentExporter.temporaryURL(for: recipe, extension: fileExtension)
        do {
            try await Task.detached(priority: .userInitiated) {
                switch format {
                case .markdown: try RecipeDocumentExporter.writeMarkdown(exportRecipe, to: url)
                case .html: try RecipeDocumentExporter.writeHTML(exportRecipe, to: url)
                }
            }.value
            recipeDocumentURL = url
            try await Task.sleep(nanoseconds: 300_000_000)
            showRecipeDocumentShare = true
        } catch { recipeDocumentStatus = "Could not export \(recipe.title): \(error.localizedDescription)" }
    }

    @MainActor private func savePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { pickedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoStatus = "The selected photo could not be read. Please choose another photo."
                return
            }
            guard let image = UIImage(data: data) else {
                photoStatus = "The selected file is not a supported image."
                return
            }
            savePhoto(image)
        } catch {
            photoStatus = "Could not load the selected photo: \(error.localizedDescription)"
        }
    }

    @MainActor private func presentPhotoPicker() async {
        imageEditButtonVisible = false
        try? await Task.sleep(nanoseconds: 250_000_000)
        showPhotoPicker = true
    }

    @MainActor private func presentCamera() async {
        imageEditButtonVisible = false
        try? await Task.sleep(nanoseconds: 250_000_000)
        showCamera = true
    }

    @MainActor private func presentImageManagement() async {
        imageEditButtonVisible = false
        try? await Task.sleep(nanoseconds: 250_000_000)
        showImageGeneration = true
    }

    @MainActor private func savePhoto(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.88) else {
            photoStatus = "Could not prepare the selected image."
            return
        }
        let name = "\(UUID().uuidString).jpg"
        let url = UserFiles.url(for: name)
        let previousCover = photos.first(where: \.isCover)
        var insertedPhoto: RecipePhoto?
        do {
            try jpeg.write(to: url, options: .atomic)
            photos.forEach { $0.isCover = false }
            let photo = RecipePhoto(recipeID: recipe.id, relativePath: name, isCover: true)
            insertedPhoto = photo
            modelContext.insert(photo)
            try modelContext.save()
            photoStatus = "The recipe photo was added."
        } catch {
            if let insertedPhoto { modelContext.delete(insertedPhoto) }
            if let previousCover { previousCover.isCover = true }
            try? FileManager.default.removeItem(at: url)
            photoStatus = "Could not save the recipe photo: \(error.localizedDescription)"
        }
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
    @State private var dinnerDate: Date

    init(recipe: Recipe, initialDinnerDate: Date? = nil, onSaved: @escaping () -> Void = {}) {
        self.recipe = recipe
        self.onSaved = onSaved
        _dinnerDate = State(initialValue: Self.defaultDinnerDate(on: initialDinnerDate))
    }

    private static func defaultDinnerDate(on date: Date?) -> Date {
        let day = date ?? .now
        return Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day).map { max($0, .now) } ?? .now
    }

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
            if let usage = usages.first(where: { $0.id == existing.id }) { usage.dinnerDate = dinnerDate }
        } else {
            let entry = PlannedDinnerRecipe(recipeID: recipe.id, dinnerDate: dinnerDate)
            context.insert(entry)
            context.insert(RecipeDinnerUsage(id: entry.id, recipeID: recipe.id, dinnerDate: dinnerDate))
        }
        onSaved()
        dismiss()
    }

    private var usages: [RecipeDinnerUsage] {
        let recipeID = recipe.id
        let descriptor = FetchDescriptor<RecipeDinnerUsage>(predicate: #Predicate { $0.recipeID == recipeID })
        return (try? context.fetch(descriptor)) ?? []
    }
}

