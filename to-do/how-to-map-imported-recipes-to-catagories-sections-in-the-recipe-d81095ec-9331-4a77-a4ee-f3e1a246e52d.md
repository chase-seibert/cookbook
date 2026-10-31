## User requirements

- As a user, I want imported recipes mapped to an existing category when their source category matches, and otherwise assigned to the default category I set in Category Manager, so that imports never create categories automatically or block on category selection.
- As a user, I want to change any recipe's category from its ellipsis menu, so that I can organize individual bundled or imported recipes where I need them.
- As a user, I want to manage categories and choose the default in Settings, so that the list sections and import fallback match how I organize recipes.
- As a user, I want to choose a replacement category when deleting a category that contains recipes, so that those recipes remain organized and visible.

Assumption: if the default category is deleted, Category Manager must require choosing another existing category as the new default before deletion completes.

## Architecture and data model

The bundled categories come from `recipes/index.json` as `CookbookCatalog.categoryOrder`. `Recipe.category` is currently a string; the Paprika reader uses the first source category or the invented fallback `Imported`, and `RecipeBrowserView` appends categories found on recipes. Remove this runtime category discovery so recipe data cannot create browse sections.

Add a persisted category registry initialized from the bundled category order, with stable category IDs, names, ordering, and the selected default. Persist category definitions and per-recipe category assignments in SwiftData (or an equivalent repository-backed store) so category edits apply to bundled and imported recipes consistently. Resolve legacy bundled category names to seeded IDs, and retain existing imported recipe categories when they map to seeded categories; use the default for legacy values with no match. A schema migration or compatible new model registration is needed if SwiftData stores the registry and overrides. Renaming a category keeps its ID; deleting one atomically reassigns its recipes to the category selected in the confirmation flow before removing it.

At import, normalize each Paprika source category and match it only against existing registry names/aliases. Use a unique match when available; otherwise assign the configured default. Persist the selected category ID with the imported recipe assignment. Recipe detail's ellipsis menu opens a category picker that updates the same assignment record; it must work for bundled recipes without editing generated catalog files. Category Manager controls category creation, rename, ordering, default selection, and deletion with recipe reassignment.

## Basic test cases

- Import a recipe whose Paprika category uniquely matches an existing category: it is assigned there and appears under that section.
- Import a recipe with no category, an unknown category, or an ambiguous match: it is assigned to the configured default; no new section appears and import review remains usable.
- Change the default in Category Manager and import an unmatched recipe: it lands in the newly selected default category.
- Use a bundled recipe's and an imported recipe's ellipsis menu to change category: each appears in the chosen section after saving and relaunching.
- Add, rename, and reorder categories in Settings: the updated list persists and all assignments remain associated with the intended categories.
- Delete an empty category: it is removed. Delete a category with recipes: the app asks for a replacement, then all affected recipes move there before the category is removed.
- Delete the current default category: require a replacement default, and verify later unmatched imports use it.
- Cancel category deletion or its reassignment prompt: category and recipe assignments remain unchanged.
- Search and existing category browsing continue to work across bundled and imported recipes after category changes.

## High-level implementation details

1. Add the persisted category registry, assignments, seeded IDs, and default selection. Migrate legacy imported categories to registry IDs and preserve the bundled catalog as the source of initial categories and recipe content.
2. Add Category Manager to `SettingsAndDinner.swift` with create, rename, reorder, default selection, and deletion. For a used category, require a replacement category and apply all assignment changes plus deletion in one transaction; similarly require a new default before deleting the current default.
3. Update `PaprikaImportReader` to preserve source category strings as matching input without creating a category or using an “Imported” category. Resolve a unique existing match or the saved default, then validate the target exists before `PaprikaImportStore.add` writes recipes or photos.
4. Add category editing to the recipe detail ellipsis menu, backed by persistent per-recipe assignments for both bundled and imported recipes. Keep the category picker limited to registry entries.
5. Update import review to show the resolved destination category, and update `RecipeBrowserView` to render sections exclusively from the registry in its configured order.
6. Add focused tests for seeding/migration, source matching and default fallback, category edits, used-category deletion reassignment, recipe-level category changes, and browser section membership. Run `make catalog-check`, the relevant iOS test/build workflows including `make phone-build`, and visually check Settings, import review, recipe detail, and Recipes sections on a simulator. Do not deploy as part of this task.

Material risks are data loss during category edits and imports persisting an invalid assignment. Use stable category IDs, apply rename/reassignment transactionally, and reject any import assignment whose category no longer exists before writing its records or photos.
