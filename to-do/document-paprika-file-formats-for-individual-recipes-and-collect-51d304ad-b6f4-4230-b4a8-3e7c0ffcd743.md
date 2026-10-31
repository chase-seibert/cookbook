## User requirements

- As a user, I want clear documentation of individual `.paprikarecipe` files and collection `.paprikarecipes` exports, so that I can inspect, back up, and build compatible tooling for them.
- As a user, I want to export a recipe from its detail view as a `.paprikarecipe` file, so that I can share or move that recipe to Paprika or another compatible tool.
- As a user, I want to export all recipes in one `.paprikarecipes` file, so that I can transfer or back up the app’s recipe library in one operation.

Assumptions to resolve in implementation: “all recipes” means the complete combined library currently shown by the app (bundled catalog plus device-local Paprika imports), independent of active browse filters. Exported UIDs need a stable policy for bundled recipes and should preserve existing Paprika UIDs for imported recipes. The current importer confirms only a subset of Paprika’s schema; documentation must label observed importer behavior separately from format behavior that still needs validation against representative Paprika-generated files.

## Architecture and data model

No material persistence schema or catalog change is required. Build an export conversion layer from the existing `Recipe` value and the separate `ImportedPaprikaRecipe` records into Paprika-shaped JSON. Reuse existing source IDs/UIDs where appropriate, but settle a stable UID mapping for bundled records before implementation so repeated exports do not create new identities.

An individual export is a UTF-8 JSON recipe compressed as gzip and given a `.paprikarecipe` extension. An all-recipes export packages those gzip recipe files as entries in one ZIP container with the `.paprikarecipes` extension. Preserve the app’s current separation between generated Markdown/catalog recipes and device-local imported records; export must not rewrite either source. Resolve each recipe’s cover media from its existing asset or `RecipePhoto` record and encode only fields whose Paprika representation is supported. No app-owned identity, notes, cooking history, or other non-Paprika data should be implied to survive this interchange.

Update `docs/paprika-import-formats.md` into a format and export reference. Separate confirmed behavior (including what this app’s reader accepts) from undocumented or version-specific Paprika details. Cover archive and compression layers, encoding, observed fields and value types, photo/media fields, unsupported or unknown fields, and small sanitized examples for both extensions. A generated example should be labeled as Cookbook output, not as proof of an official Paprika specification.

## Basic test cases

- Export a bundled recipe from its detail view; the result has a `.paprikarecipe` name, is a gzip stream containing valid UTF-8 JSON, and contains the mapped title, ingredients, directions, servings, source, category, and stable UID.
- Export an imported recipe and verify its Paprika UID and supported content are retained; verify its cover is included when available and unsupported media is handled without corrupting the file.
- Export the complete library and verify the `.paprikarecipes` output is a readable ZIP containing one valid `.paprikarecipe` entry per exported recipe, with no recipes omitted because of current search/filter state.
- Open both outputs with the existing Paprika reader; confirm the individual file yields one preview and the collection yields all expected previews. Round-trip loss of fields not represented in `Recipe` is documented.
- Export a collection containing zero recipes or a recipe with invalid/unavailable media; present a clear failure or defined empty-library behavior without sharing a partial archive.
- Verify cancellation, sharing, and filesystem/write failures do not mutate recipes or leave a misleading success state.
- Inspect the docs’ sample JSON and archive listing against the described format layers, and ensure confirmed versus uncertain claims are visibly distinguished.

## High-level implementation details

1. Inspect representative Paprika-generated individual and collection exports, including examples with photos, to verify container metadata, filenames, compression, field types, and UID conventions. Treat current `PaprikaImportReader` support as evidence about this app’s accepted inputs, not a complete Paprika specification. Keep examples sanitized and small.
2. Extend `docs/paprika-import-formats.md` with the observed format description, a field/type table, photos and other media notes, app-specific import limits, and representative individual/collection examples. Mark unanswered or version-dependent details explicitly.
3. Add a focused export encoder alongside the Paprika import implementation: map `Recipe` into Paprika JSON, generate deterministic valid UIDs where no Paprika UID exists, gzip each recipe, and write the collection ZIP. Use bounded, collision-safe filenames and atomic output; report encoding, media, or archive failures rather than producing a partial file.
4. Add a single-recipe share action to the recipe detail UI and an “Export all recipes” action in Settings. Feed the exporter the unfiltered combined catalog and imported records, resolve cover photos, write a temporary shareable file, and expose it through the existing `ShareLink` pattern. Keep the export work off the main thread where practical and show a useful status on failure.
5. Verify with focused generated fixtures and the existing reader, including UTF-8/non-ASCII text, a cover photo, multiple recipes, duplicate-name recipes, stable UIDs across repeat exports, and archive/compression failures. Then run relevant Makefile checks and an iOS build; distinguish build evidence from actual share-sheet/device interaction evidence.

Unresolved decisions: confirm Paprika’s accepted UID shape and ZIP entry naming from real exports; decide how to map categories and fields that do not have a direct `Recipe` equivalent; determine which image formats/size limits can be emitted compatibly; and confirm that “all recipes” includes every imported record as well as bundled recipes.
