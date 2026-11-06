## User requirements

- As a user, I want playful, cooking-themed status messages while an LLM imports a recipe, so that the wait feels more engaging.
- As a user, I want the messages only while extraction is actually pending, so that the review and error states remain clear.
- Assumption: apply this to both current LLM recipe import flows (Safari page capture and magazine photo), since both show the same extraction wait.

## Architecture and data model

No material architecture, persistence, or data-model change is required. The messages are transient UI state; recipe extraction, validation, saving, and SwiftData records remain unchanged. Reuse one small SwiftUI status component or message source in both review views so wording and cycling behavior stay consistent. The sequence should avoid implying measurable extraction progress.

## Basic test cases

- Start a Safari recipe import and a magazine-photo import: each shows a humorous cooking-themed message with the existing indeterminate progress indicator.
- Leave extraction pending long enough to advance the message: the displayed message changes and remains readable without suggesting a percentage or completed step.
- Complete extraction: the loading message disappears and the existing recipe review appears.
- Cause extraction to fail: the existing error alert appears, with no loading message left behind; choosing Try Again restarts the loading state and message sequence.
- Cancel during extraction: dismissing the import also ends its loading presentation without affecting another import screen.
- Check VoiceOver and Dynamic Type: status copy is announced/readable and does not crowd out the progress indicator or controls.

## High-level implementation details

1. Add a concise set of family-friendly, cooking-related status lines and a shared SwiftUI presentation for them, keeping the existing progress indicator and import-specific explanatory context where useful.
2. Show and cycle messages only while each view's `isExtracting` state is true. Restart the sequence on retry and stop updates when extraction finishes, errors, or the view is dismissed. Keep the sequence bounded or repeat it without claiming progress.
3. Replace the duplicated static loading copy in `WebRecipeImport.swift` and `MagazineRecipeImport.swift` with the shared presentation; leave the independent webpage-image loading task and recipe extraction behavior untouched.
4. Verify both paths through success, delayed response, retry/error, and cancellation states, including accessibility sizing. For implementation, follow the repository app workflow: run `make sim-build` and `make phone-deploy` after the code change; fix and rerun if either fails. No recipe catalog or PDF regeneration is needed.

Possible rotating status messages:

1. Whisking the recipe into shape…
2. Asking the onions to share their secrets…
3. Convincing the tomatoes to stick together…
4. Counting the noodles. They keep moving…
5. Preheating the pun oven…
6. Giving the garlic a tiny pep talk…
7. Making sure the cheese is grate…
8. Sorting the ingredients before they form a union…
9. Letting the flavors introduce themselves…
10. Tasting the instructions. Carefully. Virtually…

Risks: rapid or distracting copy changes could make a long wait feel worse, and an unmanaged timer/task could continue after extraction ends. Use a modest interval and tie message updates to the view's active extraction lifecycle. Exact message wording and cadence remain implementation choices.
