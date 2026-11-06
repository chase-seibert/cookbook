## User requirements

- As a home cook playing a saved multi-recipe dinner, I want the current step's ingredients and quantities on screen, so that I can prepare that step without leaving Dinner mode.
- As a home cook, I want the list to contain only ingredients assigned to the current step, like individual recipe Cooking mode, so that I can tell what to use now.
- Assumption: dinner steps continue to use their existing recipe-and-step identity; the ingredients should come from the current bundled recipe catalog.

## Architecture and data model

Dinner mode currently renders a `TimelineActivity` in `DinnerTimelineCookingView` (`ios/Cookbook/SettingsAndDinner.swift`). The scheduler already sets each activity ID to `<recipeID>:<stepID>`, and each catalog `RecipeStep` stores ingredient IDs. Resolve the activity's recipe and step from that identity, then display only the recipe ingredients whose IDs appear in that step's `ingredientIDs`, using the quantity and name treatment from `CookingModeView` in `ios/Cookbook/CookingAndGroceries.swift`.

No material architecture, persistence, or schema change is required. Saved dinner timelines already persist these activity IDs and decode them through `TimelineActivity`; keep that format. If an older or edited activity cannot be resolved, show its instruction without an ingredient list (or a small empty-state message), rather than showing every ingredient for the recipe. Steps with no assigned ingredients should also remain usable.

## Basic test cases

- Play a generated dinner step that has assigned ingredients: Dinner mode shows the matching quantities and names alongside the instruction.
- Advance to another step in the same recipe: the ingredient list updates to that step and excludes ingredients assigned only to the previous step.
- Move between different recipes, then use Previous: ingredients follow the selected activity in both directions, including when two recipes have similar titles.
- Play a step with no ingredient IDs: the instruction and navigation still work, with no unrelated ingredients shown.
- Reopen an existing saved timeline and play it: its existing activities resolve and show step ingredients without changing saved completion state.
- Encounter an activity whose recipe or step cannot be resolved: Dinner mode remains usable and does not display another step's ingredients.

## High-level implementation details

1. Give `DinnerTimelineCookingView` access to the catalog recipes and derive the current step's ingredients from the current activity ID and that step's `ingredientIDs`.
2. Parse the composite ID using the recipe ID prefix and step ID suffix (split once at the separator), then look up the matching recipe and step. Do not match by title alone because titles may be duplicated.
3. Add a compact ingredient block to the dinner step content using the same quantity/name presentation as individual Cooking mode. Keep the instruction, time, estimate, completion control, and navigation behavior intact.
4. Handle missing IDs and empty assignments safely, and preserve the existing activity encoding so saved plans and duplicated timelines remain compatible.
5. Verify generated and reopened saved timelines on a small screen, including a step with multiple ingredients and one with none. For implementation, follow the repository app verification workflow: `make sim-build`, then `make phone-deploy` after app code changes.

Risk: the existing composite activity ID relies on `:` not appearing ambiguously in either component. Confirm recipe and step ID conventions while implementing; if that convention is not reliable, add optional explicit recipe/step IDs to `TimelineActivity` with backward-compatible decoding and populate them for new schedules.
