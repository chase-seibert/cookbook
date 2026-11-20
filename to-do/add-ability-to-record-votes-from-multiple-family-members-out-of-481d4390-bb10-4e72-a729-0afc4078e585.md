## User requirements

- As a user, I want to create and manage any number of named family members in Settings, so that each person's dinner vote can be attributed to them.
- As a user, I want each family member to give a particular dinner instance a rating from 1 to 5 stars, so that votes stay attached to the meal that was actually shared.
- As a user, I want each recipe to show its aggregated star rating across dinner instances that included it, with at most one decimal place, so that I can compare how the family has rated that recipe over time.

Each recorded dinner instance is distinct, even when the same recipe is served more than once or on the same date. A dinner vote is shared across the recipes recorded as part of that instance; each such vote contributes to each included recipe's aggregate. Do not treat a planned date or saved timeline as proof that a dinner occurred. Decide whether removing a family member retains their historical votes.

## Architecture and data model

The app has no family-member, recorded-dinner, or rating model today. `PlannedDinnerRecipe` records recipe/date pairs, while `DinnerTimeline` stores a saved plan; neither represents an actual occurrence. Add SwiftData records for named family members, dinner instances, and per-member votes. A dinner instance has a stable ID, date/time, and the recipe IDs served. Each vote references one dinner instance and one stable member ID, stores an integer star value constrained to 1–5, and has an update time. Enforce one current vote per member per dinner instance in the store layer. If one instance includes multiple recipes, its member votes contribute to each included recipe's aggregate.

Provide an explicit way to record a dinner instance and the recipes served, then collect votes for it; scheduling a recipe or saving a timeline alone must not create a rated occurrence. Calculate each recipe's mean from votes on all recorded dinner instances containing that recipe and display at most one decimal place; show an unrated state when there are no votes. Decide whether the UI also displays vote count. Decide member deletion semantics before implementing persistence: retaining history may require a soft-deleted member or a voter-name snapshot; deleting votes is simpler but loses history. Register new SwiftData models in `CookbookApp.swift`. These are additive models, so existing recipe, schedule, and timeline data should remain intact without conversion; verify the app's normal SwiftData model upgrade on an existing store. Update `docs/data-model.md` and `docs/architecture.md` to describe the records, references, and aggregate calculation.

## Basic test cases

- Create several named members in Settings; each appears in the list and remains after leaving and reopening the app.
- Reject an empty or whitespace-only member name; renaming a member keeps their prior votes associated with the same member identity.
- Record two dinner instances containing the same recipe, including two instances on one date; votes remain separate by instance, and both instances contribute to that recipe's aggregate.
- Record an instance containing multiple recipes; its votes appear on that instance and contribute to each included recipe's aggregate, not to recipes absent from it.
- Change one member's vote; the existing vote is updated rather than duplicated, and the other members' votes remain unchanged.
- Verify the rating control cannot save values below 1 or above 5, and that no vote is shown as a recorded rating until selected.
- Verify a recipe with no votes shows an unrated state; aggregates across several votes are correct and display no more than one decimal place.
- With no configured members, the dinner voting area explains that members can be added in Settings and remains usable without a vote.
- Verify planning or saving a timeline alone does not create a dinner instance or affect recipe ratings; recording an instance does.
- Exercise the chosen member-removal behavior and confirm historical dinner displays remain understandable.

## High-level implementation details

1. Define the record-dinner flow for creating a stable dinner instance and selecting/confirming the recipes served. Confirm whether to show vote count with the aggregate and decide family-member removal behavior. Use one vote per member per instance.
2. Add SwiftData models and a small store API for creating, renaming, and removing members; recording dinner instances and their recipe IDs; and reading/upserting a member's 1–5 vote. Validate trimmed names and rating bounds at the store boundary; avoid duplicate votes when saving repeatedly.
3. Add a Family Members section to `SettingsView` in `ios/Cookbook/SettingsAndDinner.swift`, with add, rename, and the agreed removal flow.
4. Add a way in the Dinner experience to record a distinct occurrence, its served recipes, and each member's votes. Keep planned recipes and saved timelines separate from occurrence history unless the user explicitly records that they happened.
5. Add recipe-level aggregate ratings to `RecipeDetailView` in `ios/Cookbook/CookbookApp.swift`, deriving the mean from votes for instances that included that recipe and formatting to at most one decimal place. Avoid storing a stale aggregate when it can be derived from vote and instance records.
6. Register models in `ios/Cookbook/CookbookApp.swift` and update the data-model and architecture docs. Check behavior with a pre-existing local store to catch SwiftData schema compatibility issues.
7. Verify add/edit/remove, distinct instances of the same recipe, multi-recipe instances, vote persistence and edits, aggregate calculation/formatting, unrated state, and relaunch behavior. For app code changes, follow repository checks: run `make catalog-check`, then `make sim-build`, wait for it to finish, and run `make phone-deploy` as a background session after the simulator build completes. Review the simulator build and actual phone deployment result; no catalog regeneration is needed unless recipe or catalog-generator content also changes.
