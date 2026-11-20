## User requirements

- Create and manage any number of named family members from a dedicated Settings screen using standard form sections. Add by button or Return; enforce case- and diacritic-insensitive unique names. Edit through a pushed form, remove with a swipe action, and restore directly from a separate Removed Members section. A visible keyboard Done action dismisses name entry.
- On startup, merge older duplicate-name member rows into the earliest member ID, preserve active status if any duplicate was active, and move votes to the retained ID. If two duplicate rows rated the same occurrence, keep the most recently updated vote.
- Perform a one-time roster repair for this user's requested active members (Chase, Noelle, Henry, Owen, and Eleanor); preserve their retained IDs, add missing names, and move any other existing members to Removed Members without deleting their history. Later Settings edits must not be overwritten.
- Preserve existing family members and existing vote data during schema updates. Removing a person hides them from new ratings but retains their historical attribution and can be reversed.
- In the Dinner tab, each past or current calendar day continues to show its scheduled recipes. Add an **Add Ratings** action for those dates, opening a dedicated screen.
- In that screen, give each scheduled recipe occurrence its own rating from each family member. Repeated instances of the same recipe remain separate and are labeled by occurrence. Ratings support 0.5-star increments by tapping or pressing and dragging left/right, plus clearing a rating.
- Recipe detail shows one aggregate family rating across that recipe's individual previous-dinner votes, formatted to at most one decimal place with a vote count. Opening a recipe from Dinner uses the same aggregate view. Recipe detail does not list individual vote rows.

## Architecture and data model

`RecipeDinnerUsage.id` identifies one scheduled recipe occurrence, including repeated instances. Add `RecipeDinnerVote` with `recipeDinnerUsageID`, stable `memberID`, a `Double` star value in half-star increments from 0.5 to 5, and `updatedAt`. The store upserts one vote per family member per recipe occurrence. Keep the previous calendar-day `DinnerVote` model registered as legacy storage so earlier installs retain those rows; do not include those rows in current aggregates. Preserve `FamilyMember` rows and IDs. Update the model container, `docs/data-model.md`, and `docs/architecture.md`.

## Basic checks

- Add several people by tapping Add and by pressing Return; verify both create new rows without renaming or replacing existing members.
- Confirm the keyboard Done control is visible and dismisses the keyboard. Rename only through Edit; remove and restore members without losing IDs or votes.
- From Dinner, open a past day and Add Ratings. Verify each scheduled recipe is rated separately, including two instances of the same recipe on one day.
- Verify tapping and dragging sets 0.5-star increments; clear one rating and change one family member's rating without altering other votes.
- Verify votes stay attached to the right recipe occurrence and persist across relaunch.
- Confirm recipe detail shows only the aggregate and count, with no per-instance rating rows; both Recipes and Dinner entry points show the same aggregate.
- Confirm future dinner dates do not expose Add Ratings and that an unrated recipe shows the unrated state.

## Implementation and verification

1. Keep existing `FamilyMember` and legacy `DinnerVote` schema data. Add a separate per-recipe-occurrence rating model and validated upsert/delete methods.
2. Put family management on its own Form screen. Attach Return and an Add button to insertion, reject duplicate names, use navigation for rename, swipe to remove, and keep Restore as a direct action in the removed-members section. Show Done from this screen's keyboard toolbar.
3. Add a Dinner → date → Add Ratings route. Build screen items from `RecipeDinnerUsage` and scheduled rows, preserving distinct occurrence IDs and showing occurrence numbers for duplicate recipes.
4. Add a tap/drag half-star control, individual vote editors, and an aggregate-only recipe-detail rating.
5. Update docs and this plan. Run `make catalog-check`, then `make sim-build`; wait for it to finish before running `make phone-deploy` as a background command/session. Report device or simulator blockers precisely.
