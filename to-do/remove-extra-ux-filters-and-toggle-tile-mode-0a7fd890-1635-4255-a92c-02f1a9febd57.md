## User requirements

- As a user, I want the top-left category filter button and top-right list/grid toggle removed, so that the recipe screen has less extra chrome.
- As a user, I want the “Cookbook” title positioned higher after those controls are removed, so that the saved vertical space is used by the recipe list.
- Assumption: “filter button” means the category menu in the navigation toolbar. Keep the separate search field and label-filter chips, since the task note calls out the top-left button specifically.
- Keep the current thumbnail grid as the single recipe browsing layout; the screenshot shows tiles and the existing thumbnail-only browsing plan points in the same direction.

## Architecture and data model

No material architecture, catalog, schema, or migration change is required. `RecipeBrowserView` currently owns the category, label, and text-search state, while `browseMode` is a small `@AppStorage` preference read in both `RootView` and `RecipeBrowserView`. Remove the category toolbar control and stop using `browseMode` to select the results layout. Existing stored `browseMode` values can remain harmlessly in UserDefaults; all users will see the thumbnail grid regardless of whether the old value was `list` or `grid`.

## Basic test cases

- Open Recipes in portrait: neither the category filter icon nor the list/grid toggle appears, the title sits higher, and recipe tiles remain visible.
- In the portrait simulator, confirm search is available without guessing: either the search field is visible by default, or a visible search control can be tapped to reveal it. Enter a recipe or ingredient query and confirm results update.
- Open Recipes after a prior install has `browseMode=list`, then after one has `browseMode=grid`: both show the same thumbnail grid.
- Apply and clear a label chip: results update as before, confirming retained label filtering still works.
- Search/filter to no matches and clear them: the empty state and recovery action remain usable; the removed category toolbar menu is not required to recover.
- Rotate to landscape and back: the immersive dinner presentation and portrait title/layout remain correct, with no toolbar browse controls reappearing.

## High-level implementation details

1. In `ios/Cookbook/CookbookApp.swift`, remove the top-left category `Menu` and top-right browse-layout button from the portrait toolbar. Keep the horizontal label-filter bar and `.searchable` behavior.
2. Make the existing `LazyVGrid`/`RecipeTile` branch the only recipe-results layout, and remove the now-unused `browseMode` reads and writes from `RootView` and `RecipeBrowserView`. Leave old defaults untouched unless implementation review identifies a concrete compatibility need.
3. Adjust the navigation title presentation and surrounding top spacing so “Cookbook” visibly moves upward while remaining prominent. Preserve an obvious way to start search: verify in the portrait simulator that the field is visible by default or that a visible search control reveals it. Then search by recipe name and ingredient, and check landscape behavior and rotation.
4. Update `docs/design.md` if it describes the removed category control or list/grid switching. Verify the visible screen on the simulator at phone size, including the search entry affordance, and confirm the catalog/build checks appropriate to the app workflow; no recipe catalog regeneration is expected for this UI-only change.

The main risks are that removing toolbar items alone may not move SwiftUI’s large title upward, or that the search field may not be immediately visible after the title layout changes. Verify the rendered layout and confirm the search entry affordance in the simulator before accepting the change. No unresolved decisions beyond the stated assumption about retaining the separate label chips and search.
