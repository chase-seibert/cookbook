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
    private let recipes = CookbookCatalog.bundled.recipes
    private var categories: [String] { ["All"] + CookbookCatalog.bundled.categoryOrder }
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
            (category == "All" || recipe.category == category) &&
            (query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if browseMode == "grid" {
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
            .navigationTitle("Cookbook")
            .searchable(text: $query, prompt: "Recipes or ingredients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { ForEach(categories, id: \.self) { value in Button(value) { category = value } } } label: { Label(category, systemImage: "line.3.horizontal.decrease") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { browseMode = browseMode == "list" ? "grid" : "list" } label: { Image(systemName: browseMode == "list" ? "square.grid.2x2" : "list.bullet") }.accessibilityLabel("Switch browse layout")
                }
            }
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
        dismiss()
    }
}

