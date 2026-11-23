## User requirements

- As a user, I want to enter recipe selection from the Recipes filter menu using “Select specific recipes,” so that I can choose a custom subset to view in landscape “Let’s Eat” mode.
- As a user, I want a clear-selection action at the top of the list while selecting, so that I can remove the chosen subset directly.
- As a user, I want to switch between all recipes and my selected recipes without losing my selection, so that I can return to the same subset later.
- As a user, I want this selection to be temporary, so that I can make a focused list without creating or managing a saved collection.

Assumptions: “Select specific recipes” is an option near the top of the existing filter menu, below Favorites. It toggles the custom selection filter on and off; turning it off shows the ordinary filtered list but retains the selected IDs until explicitly cleared or the current `RecipeBrowserView` is left. Existing search, favorites, and label filters continue to combine with the custom subset. Whether selection candidates come from the full active catalog or only current browse-filter results remains unresolved.

## Architecture and data model

This is a SwiftUI state and presentation change centered on `RecipeBrowserView` and `DinnerIdeasLayoutView` in `ios/Cookbook/CookbookApp.swift`. Keep the selection mode and selected recipe IDs in separate view-local transient state: toggling the custom filter between selected and all changes only the mode, while the explicit clear action removes the IDs. Do not add a SwiftData entity, preference, catalog field, or migration. The browser should continue to own canonical filtering and ordering, then apply selected IDs only while the custom filter is active to derive the landscape paging sequence. An active custom filter with no selected recipes must remain distinct from the inactive/all mode and show an empty state. Reconcile selections against available active recipe IDs when recipes are deleted or become unavailable.

## Basic test cases

- Open the Recipes filter menu and verify “Select specific recipes” appears near the top, below Favorites. Choose it and verify the list enters selection mode with clear selected-state indicators and a clear-selection action at the top.
- Select several recipes, rotate to landscape, and verify only those recipes appear in browser order; previous/next paging stays within the chosen subset.
- Switch the custom filter off to show all ordinarily filtered recipes, then turn it on again; verify the same recipe IDs remain selected and restore the same landscape subset.
- Clear the selection and verify the selected set is empty. If the custom filter remains active, show a clear empty state rather than all recipes; turning the filter off restores the ordinary filtered list.
- Apply or clear search, favorites, or label filters while the custom subset is selected; verify the existing filters continue to combine with the subset and retained selections reappear when filters permit.
- Delete or otherwise make a selected recipe unavailable, then verify it is excluded and landscape navigation recovers to a remaining recipe or the empty state.
- Leave and reopen the Recipes browser; verify the temporary state resets and no saved collection or persistent filter was created.
- Verify portrait browsing, ordinary recipe detail navigation, Favorites behavior, and existing landscape “Let’s Eat” content and dinner action still work.

## High-level implementation details

1. In the `RecipeBrowserView` filter menu, place “Select specific recipes” directly below Favorites. Toggling it switches between all ordinary filtered results and the selected subset without deleting the saved-in-view selected IDs.
2. When custom selection mode is active in portrait, show selection affordances on recipe tiles/rows, a selected count, and a clear-selection action at the top. Give controls accessible labels and selected states. Decide whether candidates come from the full active catalog or current browse-filter results, and make the behavior predictable when a selected recipe is temporarily hidden by another filter.
3. Keep mode state separate from selected IDs so turning the filter off and back on preserves the choices. Clearing removes IDs; an active filter with no matches displays a useful empty state. Reset this temporary state when the browser view is left.
4. Derive the landscape menu sequence from existing `filtered` results and apply selected IDs only when the custom filter is active. Preserve existing ordering, paging, selection reconciliation, and dinner action. Since the navigation bar is hidden in landscape, ensure users can configure the subset from portrait before rotating and can recover from an empty selection.
5. Verify filter-menu placement, selection and clearing, toggling all/selected while preserving IDs, combined filters, rotation, paging, state reset, accessibility labels/traits, and existing landscape controls on simulator. For implementation, follow the repository’s required `make sim-build` followed by `make phone-deploy` workflow after each iOS code change.
