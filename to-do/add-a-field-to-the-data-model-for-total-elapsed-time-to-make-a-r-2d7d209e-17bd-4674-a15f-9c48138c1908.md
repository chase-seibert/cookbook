# Total recipe elapsed time

## User requirements

- As a user, I want each recipe to have a total elapsed make time, so that I can see how long to allow from starting the recipe to serving it.
- As a user, I want AI-created recipe imports and other recipe imports to populate that time, so that new recipes are useful without manual timing work.
- As a user, I want the time backfilled for all recipes already in my cookbook, so that the field is consistently useful across my library.

Assume elapsed time means wall-clock time from starting the recipe through serving, including required unattended cooking, resting, proofing, chilling, or marinating, while counting overlapping activities only once. Prefer an explicit total time supplied by the source; estimate it with AI only when absent. Preserve an unknown value when a defensible estimate cannot be produced. “All recipes” includes bundled catalog recipes and retained imported records, including soft-deleted records that can be restored.

## Architecture and data model

Add an optional integer `totalTimeMinutes` to the Codable `Recipe` in `ios/Cookbook/Catalog.swift`. `Recipe` is the shared runtime shape for the immutable bundled catalog and imported recipes. Imported Paprika, web, and magazine recipes are serialized as `recipeData` JSON in `ImportedPaprikaRecipe`, `ImportedWebRecipe`, and `ImportedMagazineRecipe` in `PersonalData.swift`; adding an optional Codable property is backward-compatible with stored JSON that lacks the key and does not require a SwiftData entity-column migration. Update all Recipe construction and copy/normalization paths so they preserve the value.

Bundled recipes are generated from `recipes/*.md` and `data/mobile/metadata.json` by `scripts/generate_mobile_catalog.py` into `ios/Cookbook/Resources/recipes.json`. Store curated backfill results in a stable-ID-keyed mobile metadata mapping and have the generator emit `totalTimeMinutes`; do not hand-edit the generated catalog. Document the field and its two storage paths in `docs/data-model.md`.

Extend the structured AI extraction draft/schema used by web and magazine-photo imports to return a nullable source total time when it is present. Map Paprika’s `total_time` value when provided. Use one shared AI estimator for imports whose source has no total; it should estimate elapsed wall-clock time from the complete recipe, account for parallel activities, and avoid summing step durations blindly. Validate the result and save it with the recipe. If estimation is unavailable, leave the value unknown and provide a retry path rather than saving a fabricated duration.

Backfill missing values in two places: generate/store reviewed estimates for bundled catalog IDs in mobile metadata, and run a resumable, idempotent AI backfill over imported recipe JSON records. Preserve existing explicit totals, include soft-deleted imports, checkpoint each successful update, and allow continuation after network or quota failures. Use the app’s existing OpenAI credential/model configuration and report progress and unresolved recipes.

## Basic test cases

- A bundled recipe with a metadata total emits the expected `totalTimeMinutes` in generated JSON; a recipe without one decodes with `nil`.
- Older stored imported-recipe JSON without the new key still decodes; encode/decode of a recipe with a total preserves it through normalization and save paths.
- Web and magazine AI extraction preserve a source-provided total, and recipe construction saves it. A missing source total invokes estimation; malformed, zero, or otherwise invalid output is rejected or left unknown.
- Paprika import maps a supplied `total_time`; when absent it uses the shared estimate path. Re-import and duplicate handling preserve existing saved values.
- Backfill covers bundled recipes and each imported record type, including soft-deleted records; skips already populated values; resumes without repeating completed work; and keeps completed updates when a later request fails.
- Long resting or overnight recipes yield an elapsed wall-clock estimate that includes required waits, while overlapping steps are not double-counted. An unavailable key, service error, or quota limit leaves the recipe unmodified and the backfill resumable.
- `make catalog-check` passes after metadata/generator changes, and `make sim-build` plus `make phone-deploy` pass after iOS code changes.

## High-level implementation details

1. Inspect every `Recipe` initializer, transformation, import entry point, and existing AI credential/model selection. Confirm there is no separate AI recipe-creation path outside the web and magazine extraction flows before finalizing call-site coverage.
2. Add the optional Codable field and propagate it through web normalization, magazine import, Paprika conversion, and any other Recipe copy paths. Extend extraction schemas/prompts and Paprika field mapping; centralize validation and AI estimation so every import path follows the same source-value-first behavior.
3. Add stable-ID keyed bundled total-time metadata and generator output, regenerate the bundled catalog with `make catalog`, and update `docs/data-model.md`. Avoid hand-editing generated files.
4. Implement a resumable backfill that enumerates bundled recipes and imported JSON records, estimates only missing values, writes imported JSON updates safely, and records progress so interruption or quota exhaustion does not discard completed work. Keep failures visible and retryable.
5. Add focused tests for Codable compatibility, extraction/mapping, estimation validation, and idempotent/resumable backfill. Run `make catalog-check`; for iOS code changes follow project instructions: run `make sim-build`, wait for completion, then run `make phone-deploy` in the background and monitor it to completion.

Risks include AI estimates varying across runs, API cost/quota limits during the library-wide backfill, ambiguity around whether user effort or total wall-clock time is intended, and long/overnight durations exceeding existing per-step estimator bounds. The plan assumes wall-clock time, source totals take precedence, existing OpenAI settings are reused, and backfill processes only missing totals. If any assumption is wrong, settle it before implementation; do not mark recipes complete when an estimate failed.
