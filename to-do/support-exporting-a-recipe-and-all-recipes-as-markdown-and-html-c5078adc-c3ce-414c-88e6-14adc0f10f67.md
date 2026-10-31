## User requirements

- As a user, I want to export a recipe as Markdown or HTML from its detail view, so that I can share or reuse its contents in common formats.
- As a user, I want to export all recipes as Markdown or HTML from Settings, so that I can share or back up my whole active recipe library in a readable format.

Assumptions: “all recipes” means active bundled and device-local imported recipes, independent of browse filters, with deleted recipes excluded, matching the existing Paprika bulk export. Single-recipe exports use one `.md` or `.html` file. For bulk Markdown, prefer an archive containing one valid recipe Markdown file per recipe; bulk HTML can be one standalone HTML cookbook. Confirm whether a combined Markdown document is preferred before implementation. The export contains recipe content represented by the app, not notes, photos, or other personal app data unless separately decided.

## Architecture and data model

No material persistence, catalog schema, or migration change is required. Add a renderer/export layer that converts the existing `Recipe` model to UTF-8 Markdown and escaped HTML, then writes shareable temporary files using the app’s existing share-sheet patterns. The repository’s `recipes/*.md` remain authoritative for the bundled catalog, and the app’s imported records remain device-local; exporting must not write back to either source.

Markdown should follow `cookbook-recipe/v1` front matter and section conventions from `docs/recipe-markdown-format.md`, including stable recipe IDs, quantities, steps, and notes where represented. The iOS `Recipe` model flattens some source structure (for example, ingredient groups and ordered mixed content), so the renderer must use a consistent readable approximation and must not claim byte-for-byte source reproduction. HTML must escape recipe text and produce a complete UTF-8 standalone document. A bulk Markdown archive preserves one independently valid Markdown recipe per file; the bulk HTML output can reuse the repository’s simple cookbook presentation concept, generated from the app’s combined in-memory collection rather than the source-only `make html` command.

## Basic test cases

- Export a bundled recipe and an imported recipe individually as Markdown; each file has a stable ID, title, quantities, ingredients, instructions, and represented notes, and opens as readable Markdown.
- Export those recipes individually as HTML; each file is standalone, displays the same recipe content, and treats text containing `<`, `>`, `&`, quotes, and non-ASCII characters as text rather than markup.
- Export all recipes in each format and verify every active bundled and imported recipe appears exactly once, regardless of current browse filters, while deleted bundled and imported recipes are omitted.
- Verify bulk Markdown output follows the chosen packaging decision and every per-recipe Markdown file validates as `cookbook-recipe/v1`; verify bulk HTML has a complete document structure and navigable recipe headings if an index is included.
- Export an empty library or a recipe with sparse/empty optional fields; show a clear error or defined empty state without offering a stale or partial file.
- Verify duplicate or unsafe titles produce collision-safe filenames, repeated exports remain valid, and write failures leave no success state or recipe mutations.

## High-level implementation details

1. Add a focused export renderer near the recipe model or Paprika export code. Map recipe fields to the documented Markdown format and HTML structure; make handling of flattened ingredient groups and instruction sections explicit. Escape all HTML text and attribute values.
2. Add format choices to the existing single-recipe export menu in `ios/Cookbook/CookbookApp.swift` and the existing all-recipes export section in `ios/Cookbook/SettingsAndDinner.swift`. Keep Paprika export available and share generated Markdown/HTML through the existing `ActivityView` or `ShareLink` flow.
3. For bulk export, construct one canonical active collection from non-deleted bundled recipes and non-deleted imported records, then render the selected output without applying browse filters. Resolve the open packaging decision for bulk Markdown before implementation; generate collision-safe filenames and avoid exposing partial outputs.
4. Keep generation off the main actor where practical, write UTF-8 data atomically to temporary shareable files, and surface clear status for empty-library, rendering, and file-write failures. Add concise usage documentation only if needed to explain the exported formats and bulk packaging.
5. Verify field preservation and format validity with representative bundled/imported fixtures, special characters, duplicate titles, deleted records, and empty or failed-write paths. Run `make catalog-check`, `make sim-build`, and the phone-target build for iOS implementation changes; do not deploy automatically. Treat successful builds separately from manual share-sheet/device verification.

Material risk: the app’s flattened `Recipe` model cannot reproduce all formatting and source ordering from the repository Markdown. Also settle whether bulk Markdown is an archive of individually valid recipe files or one combined document before choosing the user-facing action and filename.
