## User requirements

- As a home cook, I want recipe opens and completed grocery-add flows counted for that recipe, so that the cookbook team can use those counts as a signal of recipe popularity.
- As a cookbook maintainer, I want the counts available in a reviewable form, so that I can compare recipes over time.
- Assumption: counts are stored locally on this device and keyed by the catalog's stable recipe ID. This does not represent popularity across multiple users or devices.
- Count one grocery addition when the user successfully completes the Add to Groceries flow from a recipe. The count is per flow and does not depend on how many ingredients were added.
- Whether the team needs counts aggregated across users or devices remains an open product decision; local counts alone describe this installation.

## Architecture and data model

- Add a small SwiftData statistics record keyed uniquely by stable `recipeID`, with separate recipe-open and completed-grocery-flow counters and an update timestamp. Keep the bundled recipe catalog immutable; do not add mutable counts to generated catalog JSON.
- Count an open when the user activates a recipe in the browser, not whenever the detail view appears again. Route the list and grid entry points through the same recording operation so returning from a sheet or navigating back does not inflate opens. Include other user-facing recipe-open entry points if present.
- Count a grocery addition once when EventKit confirms successful completion of the add flow for the recipe passed to `GroceryReviewView`. Multiple committed ingredients in one flow still increment the recipe counter by one. Do not count cancelled, duplicate-only, or failed flows.
- Extend the existing SwiftData container in `CookbookApp.swift` and keep writes behind a small statistics store/repository. Review the store's schema evolution and migration behavior so adding the model preserves existing notes, photos, cooking progress, and dinner data.
- Provide a maintainer-readable summary or export of per-recipe counts. The current app has no analytics backend; cross-device or multi-user aggregation would require a separate collection and privacy design and is outside the local-storage assumption.

## Basic test cases

- Open a recipe once from list view and once from grid view; its open count increases once for each deliberate navigation, and other recipes remain unchanged.
- Re-render or return to an already-open detail view, show a sheet, or switch browse layout; no extra open is recorded without another recipe activation.
- Complete the add flow with one selected ingredient and with several selected ingredients; each successful flow increments that recipe's grocery counter exactly once.
- Cancel review, select only duplicates, deny Reminders access, use an unavailable/read-only list, or encounter EventKit save/commit failure; the grocery-flow counter does not increase.
- Relaunch the app and verify counts persist, stable recipe IDs still resolve to the correct titles, and existing personal SwiftData records remain available.
- Review or export the summary with zero-count and missing-catalog recipe IDs; it handles empty data and does not crash or misattribute counts.

## High-level implementation details

1. Preserve the agreed metric definition: count deliberate recipe opens and one successful grocery-flow completion per recipe, regardless of ingredient quantity. Confirm whether local-device counts meet the team's goal or whether cross-user analytics is required.
2. Add a uniquely keyed SwiftData model for per-recipe counters and a repository method that performs targeted increments. Integrate it into the app's model container and assess schema migration against existing stores.
3. Instrument the shared browser navigation action for recipe opens, covering list and grid modes without recording SwiftUI lifecycle appearances. Inspect other recipe-opening routes and reuse the same action where appropriate.
4. Update `GroceryReviewView` so the recipe counter increments once after the add flow completes successfully. Do not increment per ingredient; leave the counter unchanged for cancellation, duplicate-only/no-op, or failed completion.
5. Add a simple maintainer-facing count summary or export, keyed by stable recipe ID and joined to current catalog titles; make local-only scope visible in the documentation.
6. Add focused tests showing that one-item and multi-item successful flows each count once, while cancellation, duplicate-only/no-op, and failure paths do not count. Verify persistence and migration behavior and inspect a sample summary. Main risks are EventKit partial failures and treating one device's usage as broad popularity data.
