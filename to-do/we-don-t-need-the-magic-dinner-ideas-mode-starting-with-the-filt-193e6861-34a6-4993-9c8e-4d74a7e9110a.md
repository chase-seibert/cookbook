## User requirements

- As a user, I want the Recipes list to keep its search, category, and label filters, so that I can narrow the recipes I want to consider for dinner.
- As a user, I want an active filter chip to show the full selected label name, such as “Beef,” so that I can tell which filter is applied without decoding an initial.
- As a user, I want rotating my phone to landscape to switch those filtered recipes into the dinner ideas layout, so that I can browse meal ideas without a separate guided mode.
- As a user, I want rotating back to portrait to return to the filtered list with my selections intact, so that I can move between browsing and the dinner presentation naturally.
- Assumption: the current filtered recipe results define the dinner ideas; do not add a hidden dinner-only classifier or ask for wizard choices.

## Architecture and data model

This is a SwiftUI presentation and state-flow change centered on `RecipeBrowserView`, its `labelFilterBar`, `DinnerLabelDiscoveryView`, and `MenuModeRecipeView` in `ios/Cookbook/CookbookApp.swift`. Use the browser’s existing `filtered` results as the menu presentation’s source, and drive the presentation from the available layout size/orientation. In the filter bar, show the selected label’s full `displayName` in its active chip instead of only the first character; retain active styling, dropdown behavior, and VoiceOver labeling. Retain the current landscape menu composition, recipe artwork, description/pairings, paging, and dinner action where they fit the new entry flow. Remove the explicit Dinner ideas toolbar action and the progressive wizard/sheet path that it opens.

No material data-model, catalog, persistence, or migration change is required. Keep search, category, label, and browse-layout state owned by the Recipes screen; rotation should not clear or rewrite it. Avoid locking device orientation: adapt the screen when the phone rotates and let the system continue to control rotation.

## Basic test cases

- In portrait, open Recipes and verify the normal filtered list and existing filter controls are visible, with no separate Dinner ideas wizard entry.
- Select “Beef” in its label group and verify the active chip reads “Beef,” not just “B”; verify clearing/replacing the choice updates the full chip text and selected styling.
- Select a longer label and verify its full name remains readable in the horizontally scrolling filter bar on a narrow phone; verify other filter chips remain reachable by scrolling.
- Set search, category, and multiple label-group filters; rotate to landscape and verify the menu layout contains only matching recipes and paging follows the filtered result order.
- Rotate back to portrait and verify the same filters and corresponding list results remain selected.
- Change or clear filters, rotate again, and verify the landscape candidate set updates to the new results.
- With filters that produce no results, verify both orientations show a clear empty state and the user can change or clear filters.
- Verify first/last recipe navigation does not wrap, and missing artwork or optional menu description/pairings leave a usable presentation.
- Verify rotation while a recipe detail or another sheet is presented does not unexpectedly dismiss it or present a second menu layer; define and validate the intended transition for those active presentations.

## High-level implementation details

1. In `RecipeBrowserView`’s `labelFilterBar`, render `selected.displayName` for an active chip rather than `String(selected.displayName.prefix(1))`; preserve its active styling, accessibility label, and horizontal scrolling behavior. Retain the filter state and filtered result computation, but make the body respond to portrait versus landscape geometry. Portrait keeps the existing list/grid browsing and filter controls; landscape presents the filtered results in the dinner ideas menu layout.
2. Adapt the menu presentation to accept the browser’s current recipe collection and a stable selected recipe ID/index. Initialize the selection from the first filtered recipe, keep paging within that collection, and handle the collection becoming empty or changing after filters are edited.
3. Remove the toolbar button, `showDinnerDiscovery` presentation state and sheet, and the obsolete `DinnerLabelDiscoveryView` wizard. Keep recipe navigation and the existing dinner planning/grocery action connected to the currently displayed recipe.
4. Review rotation behavior on a phone in portrait and landscape, including transitions with active navigation, search/filter controls, empty results, and menu paging. Add focused UI coverage for filter preservation and result-set updates; use the repository’s iOS verification targets during implementation. No catalog generation or physical deployment is needed for this presentation-only change.

Key risks are SwiftUI navigation/sheet presentation during size changes, keeping the selected recipe stable when filtering changes, and avoiding a landscape layout that competes with the filter controls. Confirm whether landscape should expose editable filters in that layout or use the already-selected filters and rely on portrait for filter editing; keep the selected filters visible or readily recoverable either way.
