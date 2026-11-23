# Editing a note sometimes comes up with a blank screen

## User requirements

- As a user, I want tapping an existing recipe note to reliably open its editor with the saved text and related step, so that I can review and change the note.
- As a user, I want to save or cancel an edit and return to the recipe, so that note edits are predictable and do not lose existing content.
- Scope assumption: this task concerns the intermittent blank screen when editing an existing note. Adding, deleting, and exporting notes should keep their current behavior unless investigation shows they share the presentation defect.

## Architecture and data model

The note editor is presented from `RecipeDetailView` in `ios/Cookbook/CookbookApp.swift`. Editing currently uses a Boolean presentation flag plus an optional `RecipeNote`; the sheet's content is conditional on that optional value. This split state can allow a presented sheet to have no editor content. Prefer making the selected note itself drive presentation with SwiftUI's item-based sheet API, so there is no presented edit sheet without a note.

No material architecture, persistence, schema, migration, or compatibility change is expected. Keep `RecipeNote` and `NoteEditorView`'s current persistence semantics: initialize fields from the selected note, update its text and step on Save, and leave it unchanged on Cancel. Confirm that dismissing or replacing the selection clears presentation state cleanly.

## Basic test cases

- Tap an existing note: the note editor appears and shows the saved text and current related-step selection.
- Change the text or related step and tap Save: the editor closes; the recipe shows the updated note, which remains updated after leaving and reopening the recipe.
- Change a note and tap Cancel: the editor closes and the previously saved text and step remain unchanged.
- Open and dismiss different notes in succession, including rapid taps: every presented editor corresponds to the tapped note; no blank sheet appears.
- First, try to reproduce the reported blank screen with existing notes, repeating the edit flow and recording the steps and conditions when it occurs; use those steps as a regression scenario if reproducible.
- Attempt to edit a note that becomes unavailable before presentation: the app remains usable and does not leave an empty modal onscreen.
- Add a new note through the existing Add Note action: the blank new-note editor still opens and saves as before.

## High-level implementation details

1. First try to reproduce the reported blank screen by editing existing notes repeatedly, varying note selection and dismiss/reopen timing; record the reproduction steps and conditions if it occurs. Keep the observed outcome as the baseline for debugging and regression checks.
2. Inspect the note edit trigger and all note-related sheet modifiers in `RecipeDetailView`; compare the current behavior with the reproduction steps and confirm the empty-content path and interactions with the separate Add Note sheet.
3. Replace the edit Boolean plus conditional optional-note sheet with selection-driven presentation using the existing identifiable `RecipeNote`. Keep the add-note presentation separate unless the inspection shows a shared modifier conflict.
4. Preserve the current editor initialization, Save, Cancel, and SwiftData update behavior. Ensure an unavailable selection dismisses safely rather than rendering an empty sheet.
5. Verify the reproduction steps and other scenarios above, including repeated and rapid note selections. Add focused UI coverage if the project has a practical SwiftUI presentation test seam; otherwise document the manual device/simulator checks performed.
6. Run `make sim-build` and wait for it to finish, then run `make phone-deploy` in the background and monitor it to completion, following the repository workflow. Address any change-related build failure and rerun the required workflow. The main risk is changing sheet routing in a view that already presents several independent sheets; verify add-note and neighboring modal actions still work.
