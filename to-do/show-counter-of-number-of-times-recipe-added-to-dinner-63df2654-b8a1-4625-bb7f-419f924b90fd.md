# Recipe Dinner Usage and Popularity

## Goal

Show a private, on-device signal for how often each recipe has been added to a planned dinner, with a date that gives context to the count. Establish event-level data that can later support all-time favorites, favorites over a recent window (for example, the last 6 or 12 months), and optional AI meal suggestions.

## Current architecture

- Recipe identity is the stable `Recipe.id` string shared by bundled and imported recipes; there is no central SwiftData `Recipe` row.
- `PlannedDinnerRecipe` stores the current planned occurrence (`recipeID`, `dinnerDate`, `addedAt`) and can be deleted when a recipe is removed from a dinner.
- `AddRecipeToDinnerView.save()` updates an existing entry for the same recipe and calendar day or inserts a new entry. Thus confirming an already scheduled recipe on that day is not a new dinner addition.
- `RecipeUsageStats` currently stores open and grocery-flow aggregates. `RecipeDetailView` renders “My notes” near the end of recipe content.
- Dinner planning is local to the device. There is currently no explicit record that a planned dinner was actually cooked.

## Recommended data model

Add a SwiftData event entity, tentatively `RecipeDinnerUsage`, with:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `UUID`, unique | Stable identity for this dinner-add event. |
| `recipeID` | `String` | Logical reference to the bundled or imported recipe. |
| `dinnerDate` | `Date` | Date/time selected for the planned dinner; supports date-window queries. |
| `addedAt` | `Date` | When the user committed the add action; distinguishes event time from planned dinner time. |

Keep these as local personal data. Do not copy the count into the bundled catalog, export it to recipe Markdown, or send it to a service. The event rows are the source of truth for derived counts and dates; avoid maintaining a second count that can drift. This event shape permits future rolling-window aggregates and AI ranking without an event-log conversion.

When a new `PlannedDinnerRecipe` is inserted, insert exactly one usage event in the same save operation. When an existing entry for the same recipe/day is merely moved to another time, update its existing event's `dinnerDate` if the implementation can reliably identify it; otherwise avoid inventing a second add. Removing a planned dinner should remove the current plan but retain the usage event, because the requested metric is how often it was added. A later explicit undo/cancel policy can revise this if desired.

## First-version UI

In the non-preview `RecipeDetailView`, add a compact personal-usage row immediately below the notes area:

- “Added to dinner N times” using the number of usage events.
- “Last added [date]” using the latest event's `addedAt` (or omit the date when there are no events).
- If a planned dinner date is more useful in context, show it separately as “Next planned [date]”; do not call a planned date “last made.”
- Keep the row available for bundled and imported recipes, and absent from import preview-only screens.
- Present zero-count state plainly (for example, “Not added to dinner yet”) without implying a missing-data error.

The event's `dinnerDate` is retained for the future 6- or 12-month usage calculation. A true “last made” date needs a later explicit completion signal (such as marking a dinner cooked or logging a cooking session); do not infer preparation merely because a planned date has passed.

## Implementation outline

1. Add `RecipeDinnerUsage` to `ios/Cookbook/PersonalData.swift` and register it in the app's SwiftData model container in `ios/Cookbook/CookbookApp.swift`.
2. Update `AddRecipeToDinnerView.save()` so creating a new planned entry and its usage event are persisted together. Preserve current same-day duplicate behavior and make the event-writing path idempotent for an existing planned entry.
3. Query the selected recipe's usage rows from `RecipeDetailView`, calculate the count and latest add date from event rows, and render the summary directly after “My notes.”
4. Update `docs/data-model.md` with the new entity, logical recipe reference, uniqueness, and query semantics.
5. Add focused coverage for event creation, same-day re-add/update behavior, retained event history after removing a plan, imported/bundled recipe IDs, and count/date presentation states.
6. Verify with `make sim-build`, then `make phone-deploy` sequentially as required by the project instructions. Review the detail view on the simulator and report actual phone deployment status.

## Acceptance criteria

- Adding a recipe to a new dinner date records one local usage event and the detail view count increases by one.
- Reopening Add to Dinner for a recipe already scheduled on the same calendar day updates its time without increasing the count.
- Removing a planned dinner does not erase the historical add event or decrement the count.
- Bundled and imported recipes both show the correct count/date; preview-only imports do not show personal usage.
- With no usage events, the UI has a clear zero state and no fabricated date.
- The latest add date is based on the event's `addedAt`; scheduled dates remain available for future time-window calculations and are not presented as confirmed meals made.
- The model remains on-device and does not alter recipe source files or generated catalog content.
- Data-model documentation matches the shipped entity and behavior.
- Simulator build succeeds and phone deployment is attempted and its real outcome recorded.

## Later extensions (out of this task's UI scope)

- Aggregate dinner events over configurable recent windows such as 6 and 12 months, then expose favorite/recent-favorite lists.
- Add an explicit “made/cooked” signal to distinguish completed meals from planned additions and use that signal for a true last-made date.
- Let AI dinner suggestions consume local usage summaries only after the user-facing AI data policy and request boundary are defined.
