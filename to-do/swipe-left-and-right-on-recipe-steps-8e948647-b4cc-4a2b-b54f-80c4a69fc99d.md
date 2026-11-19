# Swipe left and right on recipe steps

## User requirements

- As a user, I want to swipe left to advance and swipe right to go back while viewing a recipe step in cooking mode, so that I can navigate hands-free without reaching for the Previous and Next buttons.
- As a user, I want swiping to follow the same step and section order as the existing controls, so that section progress and cooking-session resume continue to work consistently.
- Scope assumption: gestures apply to the one-step cooking mode view. Existing buttons, section picker, and finish behavior remain available; a swipe at a boundary follows the corresponding button behavior.

## Architecture and data model

No material architecture or data-model change is required. `CookingModeView` in `ios/Cookbook/CookingAndGroceries.swift` already owns the current step index, section transitions, and persistence of the current step and per-section progress in `CookingSessionRecord`. Route recognized horizontal swipes through the existing step-navigation behavior so button and gesture transitions stay aligned. Keep the gesture scoped to the step content area to avoid competing with the horizontal section picker or vertical scrolling. No catalog, SwiftData schema, or migration changes are expected.

## Basic test cases

- In a recipe with multiple steps in one section, swipe left to show the next step and swipe right to show the previous step; verify the instruction, ingredients, and step count update together.
- At the first step, swipe right and verify the view stays on that step, matching the disabled Previous control.
- At a section boundary, swipe left or right and verify navigation enters the adjacent section at the same step position the existing controls select; verify the section picker and progress label update.
- At the last step, swipe left and verify it follows the existing Finish behavior. Verify a swipe at the first recipe step never exits cooking mode.
- Navigate by swipe, leave and reopen cooking mode, and verify the saved step resumes. Switch sections and verify each section's saved progress remains correct.
- Scroll a long instruction vertically and verify it scrolls without changing steps; use the section picker and buttons to confirm their interactions remain intact.
- Verify the gesture works with large text and VoiceOver enabled, while Previous and Next remain accessible.

## High-level implementation details

1. In `CookingAndGroceries.swift`, add horizontal swipe recognition to the cooking step content region and map left to the existing forward navigation path and right to the existing backward path. Reuse the current section-boundary and finish rules rather than creating a parallel navigation implementation.
2. Choose a recognition threshold/direction check that ignores short or predominantly vertical drags. Keep the section picker outside the gesture region and preserve vertical scrolling of long instructions.
3. Exercise within-section moves, section transitions, both recipe boundaries, resume persistence, and gesture conflicts on a simulator. The repository has no identified iOS UI test target for gesture automation, so include manual interaction checks unless implementation review finds a suitable existing harness.
4. Run the repository's `make test` and `make catalog-check`, then `make sim-build`. After the simulator build completes, run `make phone-deploy` as required for iOS code changes and report its actual result.

The main interaction risk is an accidental step change while scrolling text or using the horizontal section picker. Keep recognition localized, confirm vertical scroll behavior, and preserve the existing buttons as an accessible alternative.
