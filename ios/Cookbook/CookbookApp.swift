import SwiftUI
import SwiftData
import PhotosUI
import UIKit

@main struct CookbookApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
        .modelContainer(for: [RecipeNote.self, RecipePhoto.self, DinnerTimeline.self, CookingSessionRecord.self, PlannedDinnerRecipe.self])
    }
}

struct RootView: View {
    @AppStorage("browseMode") private var browseMode = "list"
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
    @AppStorage("browseMode") private var browseMode = "list"
    @State private var query = ""
    @State private var category = "All"
    @State private var selectedLabelIDs: Set<String> = []
    @State private var showDinnerDiscovery = false
    private let recipes = CookbookCatalog.bundled.recipes
    private var labelGroups: [RecipeLabelGroup] { (CookbookCatalog.bundled.labelGroups ?? []).sorted { $0.order < $1.order } }
    private var labels: [RecipeLabel] { CookbookCatalog.bundled.labels ?? [] }
    private var categories: [String] { ["All"] + CookbookCatalog.bundled.categoryOrder }
    private func labels(in group: RecipeLabelGroup) -> [RecipeLabel] {
        labels.filter { $0.groupID == group.id }.sorted { $0.order < $1.order }
    }
    private func toggle(_ label: RecipeLabel) {
        selectedLabelIDs = RecipeLabelFilter.togglingSingle(label, selectedLabelIDs: selectedLabelIDs, labels: labels)
    }
    private func clearLabels(in group: RecipeLabelGroup) {
        selectedLabelIDs.subtract(labels(in: group).map(\.id))
    }
    private var hasLabelFilters: Bool { !selectedLabelIDs.isEmpty }
    private func selectionCount(in group: RecipeLabelGroup) -> Int {
        labels(in: group).filter { selectedLabelIDs.contains($0.id) }.count
    }
    private func selectedLabel(in group: RecipeLabelGroup) -> RecipeLabel? {
        labels(in: group).first { selectedLabelIDs.contains($0.id) }
    }
    private var visibleCategories: [String] {
        let source = category == "All" ? CookbookCatalog.bundled.categoryOrder : [category]
        return source.filter { sectionName in filtered.contains { $0.category == sectionName } }
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
            return (category == "All" || recipe.category == category) &&
                (query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }) &&
                RecipeLabelFilter.matches(recipe, selectedLabelIDs: selectedLabelIDs, groups: labelGroups, labels: labels)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                labelFilterBar
                Group {
                    if filtered.isEmpty {
                        ContentUnavailableView {
                            Label("No matching recipes", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("Try changing a label, category, or search.")
                        } actions: {
                            Button("Clear filters") { selectedLabelIDs.removeAll(); category = "All"; query = "" }
                                .buttonStyle(.borderedProminent)
                        }
                    } else if browseMode == "grid" {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(visibleCategories, id: \.self) { sectionName in
                                    VStack(alignment: .leading, spacing: 16) {
                                        Text(sectionName).font(.system(.title2, design: .serif).weight(.semibold))
                                        ForEach(browserGroups(in: sectionName)) { group in
                                            VStack(alignment: .leading, spacing: 10) {
                                                if let title = group.title { Text(title).font(.headline) }
                                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                                                    ForEach(group.recipes) { recipe in NavigationLink(destination: RecipeDetailView(recipe: recipe)) { RecipeTile(recipe: recipe) }.buttonStyle(.plain) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }.padding()
                        }
                    } else {
                        List {
                            ForEach(visibleCategories, id: \.self) { sectionName in
                                Section(sectionName) {
                                    ForEach(browserGroups(in: sectionName)) { group in
                                        if let title = group.title { Text(title).font(.headline).padding(.top, 6) }
                                        ForEach(group.recipes) { recipe in NavigationLink(destination: RecipeDetailView(recipe: recipe)) { RecipeRow(recipe: recipe) } }
                                    }
                                }
                            }
                        }.listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Cookbook")
            .searchable(text: $query, prompt: "Recipes or ingredients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { ForEach(categories, id: \.self) { value in Button(value) { category = value } } } label: { Label(category, systemImage: "line.3.horizontal.decrease") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { browseMode = browseMode == "list" ? "grid" : "list" } label: { Image(systemName: browseMode == "list" ? "square.grid.2x2" : "list.bullet") }.accessibilityLabel("Switch browse layout")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDinnerDiscovery = true } label: { Label("Dinner ideas", systemImage: "sparkles") }
                }
            }
            .sheet(isPresented: $showDinnerDiscovery) {
                DinnerLabelDiscoveryView(catalog: CookbookCatalog.bundled)
            }
        }
    }

    @ViewBuilder private var labelFilterBar: some View {
        if !labelGroups.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(labelGroups) { group in
                        Menu {
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
                                Divider()
                                Button("Clear \(group.displayName)") { clearLabels(in: group) }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if let selected = selectedLabel(in: group) {
                                    Text(String(selected.displayName.prefix(1)).uppercased()).fontWeight(.semibold)
                                } else {
                                    Text(group.displayName)
                                }
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .font(.subheadline)
                            .foregroundStyle(selectionCount(in: group) > 0 ? Color.white : Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selectionCount(in: group) > 0 ? Color(red: 0.16, green: 0.31, blue: 0.19) : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .accessibilityLabel(selectedLabel(in: group).map { "\(group.displayName): \($0.displayName)" } ?? group.displayName)
                            .accessibilityHint("Opens the \(group.displayName.lowercased()) filter.")
                        }
                    }
                    if hasLabelFilters {
                        Button("Clear labels") { selectedLabelIDs.removeAll() }
                            .font(.subheadline).buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct DinnerLabelDiscoveryView: View {
    let catalog: CookbookCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLabelIDs: Set<String> = []
    @State private var showingResults = false
    @State private var browsingAll = false
    @State private var selectedRecipe: Recipe?

    private var groups: [RecipeLabelGroup] { (catalog.labelGroups ?? []).filter { $0.wizardStep != nil }.sorted { $0.order < $1.order } }
    private var labels: [RecipeLabel] { catalog.labels ?? [] }
    private func labels(in groupIndex: Int) -> [RecipeLabel] {
        guard groups.indices.contains(groupIndex) else { return [] }
        let group = groups[groupIndex]
        return labels.filter { $0.groupID == group.id }.sorted { $0.order < $1.order }
    }
    private func eligibleLabels(in groupIndex: Int) -> [RecipeLabel] {
        RecipeLabelFilter.eligibleLabels(forGroupAt: groupIndex, recipes: catalog.recipes, selectedLabelIDs: selectedLabelIDs, groups: groups, labels: labels)
    }
    private var dinnerRecipeIDs: Set<String> {
        let dinnerLabelIDs = Set(labels.filter { label in groups.contains { $0.id == label.groupID } }.map(\.id))
        return Set(catalog.recipes.filter { !Set($0.browseLabelIDs).isDisjoint(with: dinnerLabelIDs) }.map(\.id))
    }
    private var results: [Recipe] {
        catalog.recipes.filter { recipe in
            dinnerRecipeIDs.contains(recipe.id) && RecipeLabelFilter.matches(recipe, selectedLabelIDs: selectedLabelIDs, groups: groups, labels: labels)
        }
    }
    private var visibleResults: [Recipe] { browsingAll ? results : Array(results.prefix(10)) }
    private var hasProtein: Bool {
        guard let proteinGroup = groups.first else { return false }
        return labels.contains { $0.groupID == proteinGroup.id && selectedLabelIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingResults {
                    recipeIdeas
                } else {
                    wizardStep
                }
            }
            .navigationTitle("Dinner ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                if showingResults {
                    ToolbarItem(placement: .topBarTrailing) { Button("Edit choices") { showingResults = false } }
                }
            }
        }
        .fullScreenCover(item: $selectedRecipe) { recipe in
            MenuModeRecipeView(recipes: results, recipeID: recipe.id)
        }
    }

    private var wizardStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let’s find tonight’s dinner.")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("Start with a protein. Add a meal style or ingredient to narrow the ideas.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                choiceSection(at: 0)
                if hasProtein {
                    if !eligibleLabels(in: 1).isEmpty { choiceSection(at: 1) }
                    if !eligibleLabels(in: 2).isEmpty { choiceSection(at: 2) }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            recipeCountButton
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .background(.ultraThinMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedLabelIDs)
    }

    @ViewBuilder private func choiceSection(at groupIndex: Int) -> some View {
        if groups.indices.contains(groupIndex) {
            let group = groups[groupIndex]
            let available = eligibleLabels(in: groupIndex)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.displayName)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                    if groupIndex == 0 { Text("Choose one").font(.caption).foregroundStyle(.secondary) }
                    else { Text("Optional").font(.caption).foregroundStyle(.secondary) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(available) { label in
                        let selected = selectedLabelIDs.contains(label.id)
                        Button { choose(label, in: groupIndex) } label: {
                            HStack(spacing: 8) {
                                if selected { Image(systemName: "checkmark") }
                                Text(label.displayName).lineLimit(2)
                            }
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.horizontal, 12)
                            .background(selected ? Color(red: 0.16, green: 0.31, blue: 0.19) : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .overlay(Capsule().stroke(selected ? Color.clear : Color(red: 0.39, green: 0.42, blue: 0.31), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recipeCountButton: some View {
        Button {
            browsingAll = false
            showingResults = true
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hasProtein ? "See \(results.count) available recipes" : "Choose a protein to begin")
                        .font(.headline.weight(.semibold))
                    Text(hasProtein ? "Your ideas update as you choose." : "We’ll narrow the menu around your pick.")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "arrow.right").font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color(red: 0.12, green: 0.27, blue: 0.16), in: Capsule())
        }
        .disabled(!hasProtein || results.isEmpty)
        .opacity(!hasProtein || results.isEmpty ? 0.6 : 1)
    }

    private var recipeIdeas: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("No recipe ideas yet", systemImage: "fork.knife")
                } description: {
                    Text("Edit your choices to see more recipes.")
                } actions: {
                    Button("Edit choices") { showingResults = false }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("A few ideas with \(selectedProteinName)")
                            .font(.system(.title, design: .serif).weight(.semibold))
                        Text("Choose a recipe to open its menu page.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(visibleResults) { recipe in
                            Button { selectedRecipe = recipe } label: {
                                HStack(spacing: 0) {
                                    RecipeArtwork(recipe: recipe, height: 112)
                                        .frame(width: 145)
                                    Text(recipe.title)
                                        .font(.system(.title3, design: .serif).weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary).padding(.trailing, 16)
                                }
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
                            }.buttonStyle(.plain)
                        }
                        if results.count > 10 {
                            Button(browsingAll ? "Show fewer recipes" : "Browse all \(results.count) recipes") { browsingAll.toggle() }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(red: 0.16, green: 0.31, blue: 0.19), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var selectedProteinName: String {
        guard let proteinGroup = groups.first, let label = labels.first(where: { $0.groupID == proteinGroup.id && selectedLabelIDs.contains($0.id) }) else { return "tonight" }
        return label.displayName
    }

    private func choose(_ label: RecipeLabel, in groupIndex: Int) {
        selectedLabelIDs = RecipeLabelFilter.togglingSingle(label, selectedLabelIDs: selectedLabelIDs, labels: labels)
        for laterIndex in groups.indices where laterIndex > groupIndex {
            selectedLabelIDs.subtract(labels(in: laterIndex).map(\.id))
        }
    }
}

private struct BrowserGroup: Identifiable {
    let id: String
    let title: String?
    let recipes: [Recipe]
}

private struct RecipeRow: View {
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title).font(.headline).foregroundStyle(.primary)
            Text("\(recipe.ingredients.count) ingredients · \(recipe.steps.count) steps").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
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

private struct MenuModeRecipeView: View {
    let recipes: [Recipe]
    let recipeID: String
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showDinner = false
    @State private var dinnerWasSaved = false
    @State private var showGroceries = false

    private var recipe: Recipe { recipes.indices.contains(index) ? recipes[index] : (recipes.first ?? emptyRecipe) }
    private var description: String? {
        let value = (recipe.menuDescription ?? recipe.introduction)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return value.isEmpty ? nil : value
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea()
                if geometry.size.width > geometry.size.height {
                    landscapeLayout(size: geometry.size)
                } else {
                    portraitLayout(size: geometry.size)
                }
            }
            .foregroundStyle(Color(red: 0.07, green: 0.12, blue: 0.09))
            .safeAreaInset(edge: .top, spacing: 0) { header }
        }
        .onAppear { index = max(0, recipes.firstIndex(where: { $0.id == recipeID }) ?? 0) }
        .sheet(isPresented: $showDinner, onDismiss: {
            if dinnerWasSaved { showGroceries = true; dinnerWasSaved = false }
        }) {
            AddRecipeToDinnerView(recipe: recipe) { dinnerWasSaved = true }
        }
        .sheet(isPresented: $showGroceries) { GroceryReviewView(recipe: recipe) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").foregroundStyle(Color(red: 0.36, green: 0.43, blue: 0.29))
                Text("COOKBOOK").font(.system(.subheadline, design: .rounded).weight(.semibold)).tracking(2)
            }
            Spacer()
            Text("MENU MODE · AIRPLAY")
                .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color(red: 0.91, green: 0.90, blue: 0.85), in: Capsule())
            Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.weight(.semibold)).padding(8).background(.black.opacity(0.06), in: Circle()) }
                .accessibilityLabel("Close menu mode")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94))
    }

    private func landscapeLayout(size: CGSize) -> some View {
        let compact = size.height < 390
        let horizontalPadding: CGFloat = compact ? 14 : 24
        let columnSpacing: CGFloat = compact ? 16 : 28
        return HStack(spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: compact ? 11 : 20) {
                Text("\(recipe.category.uppercased())  /  MENU MODE")
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
                landscapePairingSection(compact: compact)
                eatButton(compact: compact)
            }
            .frame(width: max(0, (size.width - horizontalPadding * 2 - columnSpacing) * (compact ? 0.45 : 0.38)), alignment: .leading)
            RecipeArtwork(recipe: recipe, height: max(0, size.height - (compact ? 16 : 40)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(alignment: .leading) { pageArrow(previous: true).padding(.leading, 12) }
                .overlay(alignment: .trailing) { pageArrow(previous: false).padding(.trailing, 12) }
        }
        .padding(.horizontal, horizontalPadding).padding(.vertical, compact ? 2 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func portraitLayout(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(recipe.category.uppercased())  /  MENU MODE")
                    .font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.27))
                Text(recipe.title)
                    .font(.system(size: min(34, size.width * 0.08), weight: .semibold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                RecipeArtwork(recipe: recipe, height: min(238, max(180, size.height * 0.29)))
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .leading) { pageArrow(previous: true).padding(.leading, 10) }
                    .overlay(alignment: .trailing) { pageArrow(previous: false).padding(.trailing, 10) }
                if let description {
                    Text(description).font(.system(size: 15)).lineSpacing(2).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary.opacity(0.82))
                }
                pairingSection(compact: true)
                eatButton(compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.bottom, 22)
        }
    }

    private func pairingSection(compact: Bool) -> some View {
        let pairings = recipe.menuPairings ?? ["A crisp green salad", "Seasonal vegetables"]
        return VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Rectangle().fill(Color.primary.opacity(0.16)).frame(height: 1)
            Text("SERVE IT WITH").font(.system(size: compact ? 10 : 12, weight: .bold)).tracking(compact ? 1.2 : 2).foregroundStyle(Color(red: 0.25, green: 0.34, blue: 0.24))
            Text(pairings.joined(separator: "  ·  ")).font(.system(size: compact ? 14 : 17)).lineLimit(compact ? 2 : nil).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eatButton: some View {
        eatButton(compact: false)
    }

    private func eatButton(compact: Bool) -> some View {
        Button { showDinner = true } label: {
            Text("LET’S EAT").font(.system(size: compact ? 14 : 17, weight: .bold)).tracking(compact ? 1.6 : 3)
                .frame(maxWidth: .infinity, minHeight: compact ? 40 : 58)
                .background(Color(red: 0.12, green: 0.27, blue: 0.16), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func landscapePairingSection(compact: Bool) -> some View {
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
        .disabled(previous ? index == 0 : index >= recipes.count - 1)
        .opacity((previous ? index == 0 : index >= recipes.count - 1) ? 0.35 : 1)
        .accessibilityLabel(previous ? "Previous recipe" : "Next recipe")
    }

    private func move(by offset: Int) {
        let target = min(max(index + offset, 0), recipes.count - 1)
        withAnimation(.easeInOut(duration: 0.2)) { index = target }
    }

    private var emptyRecipe: Recipe {
        Recipe(id: "", title: "Recipe", category: "", collectionTitle: nil, sourceFile: "", sourceSection: "", introduction: "", ingredients: [], steps: [], tips: [], healthierOptions: [], thumbnailAsset: nil, labelIDs: nil, menuDescription: nil, menuPairings: nil)
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

