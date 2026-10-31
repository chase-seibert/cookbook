# Dinner planning updates

## User requirements

- As a user, I want planned dinners ordered newest to oldest, so that the most recent dinner date is easiest to find. Assumption: “newest” means descending dinner date; recipes within one date remain in dinner-time order.
- As a user, I want generated plans to avoid unnecessary gaps by overlapping steps that can safely proceed together, so that the total work-back time is realistic and reasonably compact. The planner should make cautious overlap decisions while preserving required step order, hands-on attention, full cook/rest times, temperatures, and food-safety cues.
- As a user, I want progress to appear only on the dinner date whose plan I generated, so that other dinners do not look like they are also being planned.
- As a user, I want generated saved dinners titled with their recipe names, so that I can recognize them in the saved list. Keep the dinner date and serving time below the title. If the same title is used for multiple saved dinners on the same date, leave the first plain and suffix later ones with “number 2,” “number 3,” and so on.
- As a user, I want each saved dinner row to show its total planned duration and when the first step starts, so that I know how early to begin.
- As a user, I want printing a saved dinner plan to produce a usable print/share flow, and recipe ellipsis printing to complete reliably, so that neither print action silently stops or crashes.
- As a user, I want to open Add to Groceries from a planned dinner or saved dinner plan, so that I can review the ingredients for that meal without returning to Recipes. Assumption: review ingredients across the dinner’s recipes together and preserve duplicate-Reminders handling.

## Architecture and data model

No new persistence store or schema migration is expected. `PlannedDinnerRecipe` and `DinnerTimeline` already hold dinner dates and recipe IDs. `TimelineActivity` already stores start/end times, so saved list duration and first-step start can be derived from the earliest activity and dinner time. Preserve existing saved activities and generic names when opening older timelines; newly generated plans should receive recipe-based names.

The planner currently gets per-step duration and active/passive estimates from either model, then `buildTimeline` schedules every step sequentially backward. Revise the planning contract and scheduling flow for both model providers to identify when work can safely overlap, and have a local scheduler enforce recipe step order and conservative constraints before assigning activity timestamps. Keep each step’s full duration and safety instructions. On uncertain or invalid overlap output, use the safe sequential schedule. Store the resulting timestamps in the existing `TimelineActivity` format unless implementation shows that compatibility requires an additive optional field; decode existing saved timelines unchanged.

`DinnerPlannerView` owns the date-group UI and currently uses one global `isGenerating` flag. Track the active group/date so only its button shows the planning spinner while preventing conflicting concurrent generation. Generate default plan names from the selected recipes; disambiguate exact same-date/same-name saved plans with sequential “number 2” onward suffixes. `GroceryReviewView` currently accepts one `Recipe`; generalize its input to a set of recipes, combine and de-duplicate normalized grocery names, retain staple/exclusion and existing-Reminders behavior, and keep usage statistics compatible with existing per-recipe rows.

Printing can continue to use the existing PDF renderer and share sheet. Make recipe and saved-plan print actions complete the flow directly and report empty or failed PDF generation visibly. Saved-plan export should use stored activity data and tolerate recipe IDs that no longer resolve.

## Basic test cases

- With planned dinners on several dates, date groups appear newest to oldest; entries within a date stay in dinner-time order. A single date and an empty schedule render correctly.
- Generate a plan for one of several dates. Only that date’s Generate button shows progress, and other groups do not display a spinner or start another request.
- For parallelizable steps, verify the planner overlaps only eligible work, reduces unnecessary total lead time, preserves each step’s full estimated duration, and maintains source order and required rests, temperatures, and safety cues. Uncertain/invalid overlap decisions fall back safely; sequential steps remain sequential.
- Save one generated plan and confirm its recipe names form the title, with the serving date/time below. Save another with the same title and date and confirm the second is labeled “number 2”; subsequent duplicates receive the next number. Older saved plans still open.
- For a saved plan, confirm the list row shows total span from first step start to dinner time and the first-step start date/time; verify sensible output for missing activities or a start that falls on a previous day.
- Open a saved dinner, choose Print, and verify a nonempty checklist PDF opens the system share/print sheet. Empty or non-fitting plans give a clear message without crashing. From a recipe ellipsis menu, preview and print a recipe, including a long recipe and PDF-generation failure handling.
- From a planned dinner with multiple recipes, open Add to Groceries and verify included ingredients from all recipes appear once, staples and excluded ingredients retain current behavior, and existing Reminders cannot be added twice. Repeat from a saved dinner; unresolved recipe IDs and no-ingredient plans do not crash.

## High-level implementation details

1. In `ios/Cookbook/SettingsAndDinner.swift`, reverse `dinnerGroups` date ordering, preserve same-date time ordering, and replace global spinner display with active-group state. Continue disabling conflicting generation while a request is in flight.
2. In `ios/Cookbook/AIDinnerPlanner.swift`, align both provider prompts, response schema, and validation around per-step duration plus overlap eligibility/constraints. Implement or update the local schedule builder to overlap only confidently independent work, preserve within-recipe order and safety-relevant waits, and fall back to sequential scheduling if model output is malformed or ambiguous. Do not shorten individual task durations to make the total appear smaller.
3. In `SettingsAndDinner.swift`, build default names from the selected recipe titles, disambiguate saved plans sharing a date and exact title, and add derived duration and first-step start information to saved-dinner rows. Keep saved plan dates and times visible under the title.
4. Add Add to Groceries actions to planned dinner groups and saved-plan UI. Resolve saved recipe IDs against catalog/imported recipes and pass all available recipes into a generalized review flow in `ios/Cookbook/CookingAndGroceries.swift`; preserve the current Reminders checks and per-recipe statistics.
5. Trace saved-plan checklist printing and recipe ellipsis printing through `ios/Cookbook/SettingsAndDinner.swift` and `ios/Cookbook/NotesAndPrint.swift`. Open share/print after successful PDF creation and surface failures rather than silently stopping.
6. Verify the observable cases above, then run `make sim-build` and `make phone-build` for the iOS changes. Do not deploy. The original print crash trigger and the model’s overlap quality need direct reproduction/evaluation during implementation.
