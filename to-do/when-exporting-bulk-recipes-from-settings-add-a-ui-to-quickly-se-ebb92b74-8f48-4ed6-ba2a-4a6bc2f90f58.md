## User requirements

- As a user, I want to choose one or more recipe labels before exporting a bulk Paprika collection from Settings, so that I can quickly export only the recipes I need.
- As a user, I want an explicit **All** option, so that I can still export every active recipe without clearing labels individually.
- As a user, I want to see how many recipes match my selection before preparing the export, so that I can confirm the scope.

Assumptions: this applies to the existing iOS Settings Paprika collection export. Label choices come from the bundled catalog’s curated labels, and matching follows the app’s current browse behavior: labels within the same group are alternatives, while selections in different groups must all match. Groups marked single-select continue to allow only one choice. “All” means all active bundled and imported recipes, excluding deleted recipes, as the current export does. No recipe-management or import behavior is included.

## Architecture and data model

No material architecture, persistence, catalog schema, or migration change is required. `SettingsView` already has access to imported recipes, deleted-recipe records, and the Paprika exporter. The catalog already supplies label groups and labels, `Recipe` carries label IDs, and `RecipeLabelFilter.matches` implements the current grouped matching semantics.

Add transient selection state and a focused label-selection UI in the Settings export flow. Derive the active recipe list using the same deleted-item rules as the existing export, then filter that list with the selected catalog label IDs. Pass the resulting recipes through the existing `PaprikaExporter.item` and `writeCollection` path. Keep the selection in view state only; do not persist it or alter the Paprika archive format.

## Basic test cases

- Opening the bulk export selector offers **All** and the available catalog labels grouped as they are in recipe browsing.
- Choosing a label updates the matching count and exports only active bundled or imported recipes carrying that label.
- Choosing labels in separate groups requires a recipe to match each selected group; choosing multiple labels in a multi-select group matches a recipe with any selected label in that group.
- A single-select group does not allow conflicting simultaneous selections, consistent with recipe browsing.
- Selecting **All** resets label filtering and reports the count of all active bundled and imported recipes.
- Deleted bundled or imported recipes never appear in a label-filtered or **All** export.
- A selection with no matches clearly shows zero and prevents export, or reports the existing no-recipes error without producing a shareable collection.
- For a nonempty filtered selection, the generated `.paprikarecipes` file contains exactly the matching recipes and can still be shared. Export failures continue to surface through the existing Settings status alert.

## High-level implementation details

1. In `ios/Cookbook/SettingsAndDinner.swift`, replace the immediate all-recipes export action with a selector presentation while preserving the existing share link and export status handling.
2. Add a small selection view or sheet with an **All** choice, grouped label controls, the matching recipe count, and a clear action. Reuse the bundled catalog metadata and respect each group’s `allowsMultiple` setting.
3. Build one canonical active recipe collection from non-deleted bundled recipes and non-deleted imported records. For filtered mode, call `RecipeLabelFilter.matches` with the selected label IDs and the catalog’s groups and labels; for **All**, use the complete active collection.
4. Feed only the resulting recipes into the existing Paprika item conversion and background collection writer. Keep asynchronous busy-state handling, output URL assignment, and error reporting intact.
5. Review the selector for accessibility and empty-result behavior. Verify all/filtered counts, grouped matching, deleted-item exclusion, and archive contents; run the project’s iOS simulator and phone-target builds for the implementation. Do not deploy automatically.

Material risk: unclear label semantics could surprise users if they differ from the browse filters. This plan assumes the existing grouped filter behavior is the intended rule; confirm that assumption during implementation if the selector design reveals a different intended meaning.
