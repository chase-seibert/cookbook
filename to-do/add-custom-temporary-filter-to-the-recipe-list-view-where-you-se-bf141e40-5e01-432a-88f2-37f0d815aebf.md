## User requirements

- As a user, I want to enter recipe selection from the Recipes filter menu using “Select specific recipes,” then apply my choices, so that I can view a custom subset in portrait and landscape “Let’s Eat” mode.
- As a user, I want a fixed centered Apply filter action while editing, so that I can apply my choices without scrolling back to the top.
- As a user, I want an X beside the top Filters button whenever a filter is active, so that I can clear active filters from anywhere in the recipe list.
- As a user, I want Favorites to stay separate from custom selection, while recipe labels can scope the custom selection, so that I can hand-pick recipes from a category such as Beef or Chicken.
- As a user, I want checkboxes only while editing the custom selection, so that the applied recipe list reads as a normal recipe list.
- As a user, I want to switch between all recipes and my selected recipes without losing my selection, so that I can return to the same subset later.
- As a user, I want this selection to be temporary, so that I can make a focused list without creating or managing a saved collection.

Assumptions: The filter menu offers All recipes, Favorites, and Select specific recipes. Favorites is exclusive with custom selection and recipe-label filters. Choosing Select specific recipes enters an editing view while preserving selected recipe-label filters; those labels scope the recipe candidates and continue to combine with the applied IDs. Apply filter commits the selected IDs and displays them without selection controls. Reentering selection opens the editor with prior choices checked. The top X clears active label, Favorites, and applied custom-selection filters while preserving the selected IDs for later reuse. Search clears when entering Favorites or custom selection.

## Architecture and data model

This is a SwiftUI state and presentation change centered on `RecipeBrowserView` and `DinnerIdeasLayoutView` in `ios/Cookbook/CookbookApp.swift`. Keep editor mode, applied-filter mode, and selected recipe IDs in separate view-local transient state. While editing, show recipe checkboxes and a fixed centered Apply filter action. While applied, show only selected recipes as ordinary navigable tiles with no checkboxes. Show a top X beside Filters whenever active user filters exist; it clears active filters without deleting the selected IDs used when the custom filter is reopened. Do not add a SwiftData entity, preference, catalog field, or migration. Keep Favorites exclusive with custom selection and label filters. Preserve label filters when entering custom editing so they scope candidates; continue combining them with selected IDs after Apply. The browser should own canonical filtering and ordering, then apply selected IDs only while the custom filter is applied to derive the portrait and landscape recipe lists. An applied custom filter with no selected recipes must remain distinct from the inactive/all mode and show useful empty-state text. Reconcile selections against available active recipe IDs when recipes are deleted or become unavailable.

## Basic test cases

- Open the Recipes filter menu and verify Favorites cannot combine with custom selection or label filters.
- Select a label such as Beef or Chicken, enter Select specific recipes, and verify the candidates are limited to that label; apply a subset and verify both the label and selected IDs continue to scope the portrait and landscape list.
- Choose Select specific recipes and verify checkboxes appear only in edit mode, with a fixed single-line centered Apply filter action that stays visible while scrolling.
- Apply a subset while scrolled down and verify the portrait list returns to its top, shows only those recipes without checkboxes, and landscape shows the same subset. Reopen selection and verify the same recipes are checked for editing.
- Select several recipes, rotate to landscape, and verify only those recipes appear in browser order; previous/next paging stays within the chosen subset.
- Choose All recipes to leave the custom view without losing the selected IDs, then reopen Select specific recipes and verify the same subset is restored.
- Verify the top X clears active filters and the filter badge without deleting prior selected recipe IDs; reopen Select specific recipes and verify previous choices remain checked. Applying an empty selection should show an explicit empty state rather than all recipes.
- Delete or otherwise make a selected recipe unavailable, then verify it is excluded and landscape navigation recovers to a remaining recipe or the empty state.
- Leave and reopen the Recipes browser; verify the temporary state resets and no saved collection or persistent filter was created.
- Verify portrait browsing, ordinary recipe detail navigation, Favorites behavior, and existing landscape “Let’s Eat” content and dinner action still work.

## High-level implementation details

1. In the `RecipeBrowserView` filter menu, keep Favorites exclusive from custom selection and labels. Preserve currently selected labels when entering the custom editor so they scope candidate recipes and remain combined with applied selection.
2. In the custom editor, show checkboxes and a fixed centered Apply filter action. Apply the selected IDs; reopening the editor restores those checked IDs. Applied custom results use ordinary navigation tiles without checkboxes.
3. Keep editor state, applied mode, and selected IDs separate so leaving the custom view preserves the selection until the browser view is left. An applied empty selection displays a useful empty state. Reset temporary custom state when the browser view is left.
4. Derive portrait and landscape sequences from existing filtered results and apply selected IDs only when the custom filter is applied. Preserve ordering, paging, selection reconciliation, and the dinner action. Since navigation controls are hidden in landscape, tell users to return to portrait to finish editing or recover from an empty selection.
5. Verify filter-menu placement, selection and clearing, toggling all/selected while preserving IDs, combined filters, rotation, paging, state reset, accessibility labels/traits, and existing landscape controls on simulator. For implementation, follow the repository’s required `make sim-build` followed by `make phone-deploy` workflow after each iOS code change.
