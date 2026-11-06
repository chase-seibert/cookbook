## User requirements

- As a user, I want each numbered direction in an imported recipe to become its own cooking step, so that I can advance through the recipe one instruction at a time.
- As a user, I want imported directions to keep their wording and order, so that fixing step boundaries does not change the recipe.
- Assumption: the attached screenshot is from a Paprika import. It shows directions numbered 1–7 inside one displayed step, consistent with the current Paprika parser's blank-line-only split. Confirm the import source if implementation work uncovers another path.

## Architecture and data model

No material architecture, persistence, or schema change is needed. Paprika recipes are decoded in `ios/Cookbook/PaprikaImport.swift` into the existing `[RecipeStep]` values, then persisted as the existing Codable recipe payload. Adjust direction parsing at import time to recognize numbered step boundaries at the start of lines as well as blank-paragraph boundaries, preserving continuation lines and source order. Remove recognized list numbering from each stored instruction so the recipe view's own step number is not duplicated. Existing imported records need no migration; the fix applies to future imports.

## Basic test cases

- A Paprika `directions` value containing lines `1. Rinse rice`, `2. Heat oil`, and `3. Add onion` produces three ordered steps with the instruction text intact and without the source ordinals.
- The attached recipe's seven newline-separated numbered directions produce seven separately navigable steps, numbered once in the app.
- Directions separated by blank lines continue to produce separate steps; text that wraps onto following unnumbered lines remains part of its current step.
- An unnumbered multi-line direction remains one step rather than being split at arbitrary line breaks.
- Empty direction lines do not create empty steps, and CRLF input parses the same as LF input.

## High-level implementation details

1. Add a focused direction parser in or near `PaprikaImportReader` and use it when decoding the Paprika `directions` field. Preserve the current blank-line behavior while recognizing numbered markers such as `1.` or `1)` at line starts; only split at an actual step marker, not at numbering embedded in prose.
2. Normalize line endings and trim empty boundaries. Strip only the recognized leading ordinal/list marker from each step, retaining all other punctuation and wording. Keep step IDs deterministic and sequential as they are now.
3. Add regression coverage alongside the repository's existing Swift test sources for numbered lines, paragraph-separated input, wrapped continuation text, unnumbered prose, and the screenshot's seven-step case. Verify parsed `Recipe.steps` count, order, and instruction strings.
4. Review import preview and recipe/cooking views to confirm the parsed steps display and advance individually. Run the focused test and the repository-required iOS verification (`make sim-build`, then `make phone-deploy`) when implementation changes are made; investigate and resolve any failures before treating the implementation as done.

Main risk: splitting every newline would fragment wrapped directions, while preserving source ordinals would show duplicate numbering. Keep the parser boundary rule line-aware and marker-specific. If numbered markers are inconsistent across real Paprika exports, inspect representative fixtures before broadening supported marker forms.
