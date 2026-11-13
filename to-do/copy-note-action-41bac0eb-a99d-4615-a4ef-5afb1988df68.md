# Copy note action

## User need

After writing a note about what to change the next time a recipe is made, copy its text easily so it can be pasted into Codex and used to update the cookbook recipe. The current note context menu only offers deletion.

## Expected behavior

- Add a “Copy Note” action to the existing per-note context menu in the recipe detail’s “My notes” section, alongside “Delete Note.”
- Copy that note’s complete text to the system clipboard, preserving punctuation, whitespace, and line breaks so multi-line cooking observations paste faithfully.
- Copying leaves the note and its updated timestamp unchanged. Deleting remains a separate destructive action.
- Give brief, accessible confirmation that the note was copied (for example, a temporary “Note copied” status or a native confirmation pattern) without interrupting the recipe view. If the project already has a consistent clipboard feedback pattern, follow it.

## Implementation approach

1. In `ios/Cookbook/CookbookApp.swift`, update the `contextMenu` attached to each note row near the “My notes” section. Keep the copy action scoped to the selected `RecipeNote` and retain the existing destructive delete behavior.
2. Use the platform clipboard API already appropriate for this iOS app (likely `UIPasteboard.general.string`) and add only the smallest required import or helper. Do not add persistence, alter note export, or change the note editor.
3. Provide transient, accessible success feedback after copying. Avoid displaying note content in the confirmation.
4. If a shared clipboard helper or feedback component already exists, reuse it rather than creating a parallel abstraction.

## Acceptance checks

- A note’s context menu offers both “Copy Note” and “Delete Note.”
- Selecting “Copy Note” places the full selected note text on the clipboard; a multi-line note retains its line breaks and punctuation.
- Copying does not modify, delete, reorder, or timestamp the note, and the user receives a brief confirmation.
- Selecting “Delete Note” still performs the existing soft-delete behavior and remains visibly destructive.
- Confirm behavior for two different notes to ensure the action copies the note whose menu was opened.

## Verification

- Add or update focused coverage for the note context menu and copy action if the existing UI-test setup can inspect clipboard behavior reliably; otherwise verify the menu and copy flow manually on simulator/device.
- Run `make catalog-check`, then `make sim-build` and wait for completion. After the simulator build succeeds, run `make phone-deploy` in a background session, monitor it to completion, and report its actual result, as required for iOS code changes.
