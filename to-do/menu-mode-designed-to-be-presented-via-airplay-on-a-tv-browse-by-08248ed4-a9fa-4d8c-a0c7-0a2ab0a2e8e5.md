## User requirements

- As a home cook, I want a TV-readable menu mode that I can present over AirPlay, so that my household can browse dinner ideas together.
- As a home cook, I want to choose a cookbook label and view one recipe at a time, so that I can page through a focused menu without a dense list.
- As a home cook, I want each recipe to have a large picture, a restaurant-menu-style description, and suggestions for pairings or accompaniments, so that I can picture a complete meal.
- As a home cook, I want a “Let’s eat” action on a recipe, so that I can carry that choice into dinner planning and grocery review.

Assumptions to confirm during implementation: “label” means the cookbook category already used by the recipe browser; AirPlay means presenting the app’s menu view through iOS screen mirroring; menu descriptions and pairing suggestions are reviewed cookbook copy, not generated at runtime. The exact transition after grocery review (stay in the menu or open Dinner) should be settled while designing the flow.

## Architecture and data model

- Keep LaTeX recipe files authoritative and the iOS catalog bundled and offline. Add reviewed menu descriptions and pairing data to the existing mobile metadata/catalog generation path, keyed by stable recipe IDs. Pairings should reference stable recipe IDs where they point to another cookbook recipe; accompaniment text can cover items outside the catalog. Do not derive menu copy from titles alone.
- Extend `Recipe` and the generated `recipes.json` with optional menu description and pairing fields. Bump the catalog schema version if required by the generator’s compatibility policy, and decode the new fields as optional so older bundled catalogs remain readable. This is catalog metadata only; no SwiftData migration is needed unless implementation chooses to persist user-authored menu edits, which is outside the current request.
- Add a menu presentation state to the Recipes experience: selected category, ordered recipe collection, and current recipe index. Reuse catalog order, category labels, and existing thumbnail assets, with the current neutral image fallback for missing assets. Keep personal cover photos optional and recipe-ID scoped if they are included.
- Route “Let’s eat” with the selected recipe into the existing dinner scheduling and grocery-review capabilities. Preserve the current explicit date/time choice, duplicate handling, grocery item review, and confirmation before writing to Reminders. Persist dinner selection through `PlannedDinnerRecipe`; do not create a second dinner or grocery store.
- No network, account, or external-display service is required under the screen-mirroring assumption. If native multi-screen AirPlay output is required, confirm it separately because it changes the presentation and device-testing scope.

## Basic test cases

- Enter menu mode from Recipes, choose a category, and verify only its recipes appear in cookbook order, one at a time; an empty category or no-match state gives a useful recovery action.
- Page forward and backward through the selected category, including the first and last recipe; controls do not wrap unexpectedly and the displayed recipe, image, description, and pairing suggestions stay in sync.
- Browse categories containing collection recipes and verify the category filter does not split, omit, or duplicate entries.
- Present the menu over AirPlay/screen mirroring in portrait and landscape layouts. Recipe title, image, description, category, pairing text, and navigation remain legible and operable; a missing image displays the fallback.
- Before implementing the menu UI, review both task attachments, “Menu Mode - Landscape.jpg” and “Menu Mode - Portrait.jpg,” as the visual references for the TV landscape layout and its portrait adaptation.
- Open a recipe with no reviewed menu description or pairings and verify the layout remains complete without blank or misleading copy.
- Tap “Let’s eat,” choose a dinner date/time, and verify the same recipe appears once under that date in Dinner. Add another recipe to the same date and verify both are available to planning.
- Review groceries from the selected recipe, remove an item or keep an already-listed item unselected, and confirm only reviewed items are added to the chosen Reminders list. Canceling either review leaves the dinner/grocery data unchanged as appropriate.
- Regenerate the catalog and run catalog validation; verify optional menu fields decode when present and when absent, stable recipe IDs remain unchanged, and image asset references resolve or fall back safely.

## High-level implementation details

1. Review the task-attached “Menu Mode - Landscape.jpg” and “Menu Mode - Portrait.jpg” mockups before implementation, using them as references for the landscape TV composition and portrait adaptation. Then inspect the recipe browser, recipe detail, catalog generator/validation, thumbnail assets, dinner date flow, and grocery review; retain existing Recipes, Dinner, and Settings navigation and visual style outside menu mode.
2. Define a small reviewed metadata shape for menu descriptions, recipe-ID pairings, and optional accompaniment suggestions. Populate initial entries from the recipe source and editorial review; keep unreviewed fields absent rather than inventing claims. Update `scripts/generate_mobile_catalog.py`, generated catalog output, and `Catalog.swift` together; use `make catalog` and `make catalog-check`.
3. Add a dedicated menu presentation reachable from Recipes. Provide category selection, a large image-led page, clear previous/next controls (and optional swipe navigation), a visible position indicator, and resilient missing-content states. Test Dynamic Type, VoiceOver order, contrast, and TV-mirrored portrait/landscape composition.
4. Connect “Let’s eat” to a focused dinner kickoff using the selected recipe. Reuse the date/time selection and `PlannedDinnerRecipe` behavior, then offer the existing ingredient review before Reminders writes. Make the next destination explicit and preserve cancel/back behavior and duplicate safeguards.
5. Add focused catalog and UI coverage for ordering, one-recipe paging, missing metadata/assets, pairing links, handoff state, and grocery confirmation. Verify with catalog checks and simulator interaction; separately record AirPlay/screen-mirroring behavior because simulator builds alone do not prove TV presentation. Do not deploy to a physical device without a separate explicit deployment request.

Risks and unresolved decisions: “label” could mean category or a new tag system; the plan assumes existing categories. “AirPlay” could require native external-display support instead of ordinary screen mirroring. The breadth of reviewed descriptions and pairings is not specified, so implementation should decide whether to author all recipes or a bounded initial set. Confirm the post-“Let’s eat” destination and whether grocery review is immediate or offered after scheduling.
