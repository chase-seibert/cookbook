# Allow editing recipe names

## User requirements

- As a user, I want to tap a recipe's name once and see a small popover with an Edit action, so that renaming is easy to discover and follows the existing image-edit interaction.
- As a user, I want Edit to open a dialog containing the current name, so that I can enter and save a new name without leaving the recipe.
- As a user, I want the saved name to appear consistently wherever the recipe is shown, so that the rename remains useful after I leave the detail view.

Assume renaming is available on normal recipe detail pages for both bundled and imported recipes. Follow the image controls' existing availability rules for preview-only and deleted recipes unless product direction says otherwise. Preserve the existing recipe ID and content; do not rename source files or change the checked-in catalog.

## Architecture and data model

`Recipe.title` is currently immutable in the Codable recipe value. Bundled recipes are read-only catalog content, while imported recipes are serialized in SwiftData JSON payloads. Add a small SwiftData title-override entity keyed by stable recipe ID so the feature can rename either kind of recipe without rewriting imported payloads or generated catalog files. Register the additive entity in the app's model container and verify compatibility with an existing store; no recipe-content rewrite or bulk migration is intended.

Resolve an override when preparing recipes for UI and other user-visible outputs. Ensure browser tiles, search and sorting, recipe detail, and recipe exports use the effective title so they do not disagree after a rename. Keep original catalog and imported data intact; when no override exists, display the original title. No recipe ID, relationship, or source schema change is needed.

## Basic test cases

- Tapping the title on an eligible recipe detail page shows a small popover with Edit; tapping elsewhere dismisses it.
- Choosing Edit opens a dialog prefilled with the current effective title. Cancel leaves the title unchanged; Save updates the recipe detail and browsing views.
- A saved rename remains after leaving and reopening the recipe or relaunching the app, for both a bundled recipe and an imported recipe.
- Search and alphabetical ordering use the new title, and recipe exports use the same effective title.
- Leading and trailing whitespace is removed. An empty or whitespace-only value cannot replace the current name; saving an unchanged name creates no unnecessary update.
- Existing recipes without overrides continue to display their original names, and an existing SwiftData store opens without losing recipe, photo, note, or other user data.
- Preview-only and deleted recipe details follow the agreed edit-availability rule and do not expose a save path when editing is unavailable.

## High-level implementation details

1. Inspect recipe resolution and display paths in `ios/Cookbook/CookbookApp.swift`, the `Recipe` value in `ios/Cookbook/Catalog.swift`, and the SwiftData model registration in `CookbookApp.swift`. Identify every title-dependent browser and export path that must resolve overrides.
2. Add the title-override model and a small persistence/resolution helper keyed by recipe ID. Apply overrides consistently while constructing the app's effective recipe values, leaving source catalog and imported JSON untouched. Document the entity in `docs/data-model.md`.
3. In `RecipeDetailView`, make the title a plain tappable control with a popover matching the existing image-edit affordance. Provide an Edit action and a native dialog with the current name, Cancel, and Save. Validate and trim the entered name, persist the override, update the visible recipe, and present save errors clearly.
4. Add focused coverage for title resolution, persistence across relaunch, blank input, and title-dependent browsing/export behavior. Verify the additive model works with an existing store and that unrelated recipe data remains available.
5. Run the focused checks and `make catalog-check`. Because this changes iOS code, run `make sim-build` and wait for it to finish, then run `make phone-deploy` in a background session and monitor it through completion. Review the title popover and dialog on a small screen and with VoiceOver/Dynamic Type.

Key implementation risk: a title override can appear correct on the detail page while stale original titles remain in browser/search/export paths. Resolve the override through a shared path and cover those surfaces. Confirm preview/deleted edit availability during implementation if the existing image-control rule is not the intended boundary.
