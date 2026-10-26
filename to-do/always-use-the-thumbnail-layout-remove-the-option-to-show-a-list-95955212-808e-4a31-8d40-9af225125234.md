## User requirements

- As a user, I want recipe browsing to always show the thumbnail layout, so that I can recognize dishes visually while searching and exploring the cookbook.
- As a user, I want the option to switch to a text-only list removed, so that recipe browsing has one consistent, image-first presentation.
- Assumption: “thumbnail layout” means the existing responsive recipe tile grid in the Recipes tab. Keep its search, category and label filters, category/collection grouping, recipe links, and current artwork fallbacks.

## Architecture and data model

This is a SwiftUI presentation change centered on `RecipeBrowserView` in `ios/Cookbook/CookbookApp.swift`. Use the existing `LazyVGrid`/`RecipeTile` path as the sole non-empty-results presentation and remove the compact `List` branch and layout-toggle toolbar action. `RecipeTile` already prefers a saved cover photo, then the bundled thumbnail, then a neutral placeholder, so recipes without artwork remain discoverable.

No material data-model, catalog schema, or migration change is required. The `browseMode` UserDefaults setting becomes unused; stop reading or writing it. Previously stored values can remain harmlessly in defaults unless implementation review finds a compatibility reason to remove them. Update `docs/design.md`, which currently describes switching between a title-first list and photo-first grid.

## Basic test cases

- Open Recipes with a fresh install and confirm recipes appear as image tiles without a layout-switch control.
- Reopen after a prior version saved either `browseMode=list` or `browseMode=grid`; confirm the thumbnail grid appears in both cases.
- Search by title and ingredient, filter by category and labels, and confirm matching tiles and existing category/collection groupings remain correct.
- Confirm a recipe with a saved cover photo uses it, a recipe without a saved photo uses its bundled thumbnail, and a recipe without either still has a visible placeholder and title.
- Select a tile and confirm it opens the same recipe detail page; check the grid remains usable on a narrow screen and with larger text/accessibility settings.
- Confirm dinner discovery’s existing thumbnail cards are unaffected.

## High-level implementation details

1. In `ios/Cookbook/CookbookApp.swift`, remove the obsolete `browseMode` storage declarations and toggle action, make the existing grid the only recipe-results layout, and retain the empty-results state, filtering, groups, navigation, and `RecipeTile` artwork behavior.
2. Update `docs/design.md` to describe thumbnail-grid recipe browsing and its no-image placeholder instead of a selectable list/grid.
3. During implementation, inspect the recipe grid at narrow and regular widths and with larger text; verify saved-photo, bundled-thumbnail, and placeholder paths, search/filter behavior, and tile navigation. Run the project’s appropriate iOS build/check workflow and review the final diff.

The main risk is tile density or scrolling usability on small screens and at larger text sizes. Preserve the adaptive grid and adjust its presentation only if visual review shows a real layout problem; do not add a second text-only browsing mode.
