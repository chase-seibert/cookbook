## User requirements

- As a user, I want to see active recipes in a selectable list before exporting, so that I can choose exactly which recipes go into the export.
- As a user, I want to sort that list by most recent or alphabetically, so that I can find recipes by recent use or title.
- As a user, I want to see how many recipes are selected and have a clear way to select or clear the set, so that I can verify the export contents before sharing.

Assumptions: this extends the existing Settings Paprika collection export selector, whose current action supports source, collection, and browse-label filters. Individual recipe selection should work with or without those filters, and only selected active recipes are exported. “Most recent” means most recently opened in the app. Whether the same selector should also replace the separate Markdown and HTML bulk-export actions is unresolved; those currently export the full active library.

## Architecture and data model

Extend the transient SwiftUI selection state in `SettingsAndDinner.swift` with selected recipe IDs and a sort choice. Reuse the existing active-recipe set, filter metadata, `PaprikaExporter.item`, and collection writer. The list should show recipe titles, selection state, and useful secondary context such as source or collection; sorting should reorder the visible list without changing which recipes are selected. Existing source, collection, and label filters can narrow the list, while the final export uses only checked recipes from that result.

For correct last-opened sorting, add an optional `lastOpenedAt` date to the local `RecipeUsageStats` SwiftData model and update it when an existing recipe-open event is recorded. The current `updatedAt` is not a reliable substitute because grocery-list activity also updates it. Confirm the common open path records all supported recipe types; add coverage for imported recipes if needed. This is an additive, optional SwiftData field with a lightweight migration path and no recipe-catalog or export-format change. Update `docs/data-model.md` and `docs/recipe-usage-statistics.md` to describe the timestamp. Recipes without an open timestamp sort after recipes with one; ties use case-insensitive title order for stable results.

## Basic test cases

- Open the Settings Paprika export selector and verify it shows active bundled, Paprika-imported, website-imported, and magazine-imported recipes as selectable rows; deleted recipes are absent.
- Select individual recipes across different sources, then export; the resulting Paprika collection contains each selected recipe exactly once and excludes every unselected recipe.
- Apply source, collection, or label filters and verify the list narrows accordingly; selected rows outside the visible filtered result do not get included accidentally. Clearing filters restores the full list without losing or unexpectedly adding selections.
- Switch between Most recent and A–Z and verify row order changes while the selected count and selected IDs remain unchanged. Recently opened recipes sort first; never-opened recipes follow, with deterministic title ordering for ties.
- Select all visible results, clear the selection, and verify the count and export button state; an empty selection cannot create a shareable export and produces clear guidance.
- Open bundled and imported recipes and verify their last-opened timestamp is recorded; perform a grocery-list action and verify it does not make a recipe appear recently opened.
- Relaunch after the additive model change and verify existing usage counts remain intact while older rows with no `lastOpenedAt` remain valid.
- Verify export generation errors continue to surface through the existing Settings status handling and do not leave a stale Paprika share file presented as the new result.

## High-level implementation details

1. In `ios/Cookbook/SettingsAndDinner.swift`, extend `PaprikaExportSelectorView` with a recipe list, individual selection state, selected-count summary, and a sort picker for Most recent and A–Z. Preserve accessible selected-state labels and existing cancel/export handling.
2. Keep source, collection, and label filters as optional list narrowing controls. Define list visibility and export membership from one shared matching function so displayed rows, bulk-select-visible behavior, counts, and final export cannot drift apart.
3. In `ios/Cookbook/PersonalData.swift`, extend `RecipeUsageStats` with optional `lastOpenedAt`, and update `RecipeUsageStore.recordRecipeOpen` to set it. Check recipe navigation/open recording in `ios/Cookbook/CookbookApp.swift` and import history entry points; ensure opening any supported recipe type updates the same usage record without treating grocery activity as an open.
4. Use selected recipe IDs to resolve the final recipes from the active recipe collection, then pass only those through the existing Paprika item generation and background collection writer. Keep generated file sharing and error handling consistent with the current Settings flow.
5. Document the new usage timestamp in `docs/data-model.md` and `docs/recipe-usage-statistics.md`. Add focused tests for selection/filter/sort behavior and usage-time updates, then run the repository’s iOS verification targets for an implementation: `make sim-build` and `make phone-deploy`.

Material decisions to resolve during implementation: confirm that “most recent” means last opened, and whether individual selection is limited to Paprika exports or should also apply to Markdown and HTML exports. The required iOS SwiftData addition is avoidable only if a different, explicitly accepted definition of recency is chosen.
