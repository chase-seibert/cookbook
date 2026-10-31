# Paprika recipe file formats

This note describes the Paprika interchange files accepted by Cookbook and the files Cookbook exports. Paprika does not publish a complete field-by-field schema for these files. Read the confidence labels carefully: the container layout is documented by Paprika; details of individual recipe objects are based on Cookbook's reader and publicly described examples, not a formal compatibility guarantee.

## Confidence and sources

- **Paprika documented:** Paprika describes `.paprikarecipes` as a ZIP containing individually compressed JSON recipe files and lists `.paprikarecipe` and `.paprikarecipes` as importable formats. See the [Paprika Android guide: Export Recipes](https://www.paprikaapp.com/help/android#export-recipes) and [Paprika support: export formats](https://paprikaapp.zendesk.com/hc/en-us/articles/360051324613-What-export-formats-do-you-support).
- **Cookbook reader observed:** Behavior stated in the importer column below is implemented in `PaprikaImportReader`. It describes what this version of Cookbook accepts, not every Paprika version or every field Paprika writes.
- **Community example:** An [older Paprika 2 export inspection](https://yabukurosawa.wordpress.com/2012/09/30/paprika-recipe-manager-for-ipad-export-format/) reports gzip-compressed JSON entries, a UUID-looking `uid`, newline-delimited text, and Base64 `photo_data`. It is useful corroboration, but is old, incomplete, and not an official schema.
- **Cookbook output:** Examples below show fields emitted by this app. They are not Paprika-generated samples and have not been validated by opening them in Paprika itself.

No representative Paprika-generated export file was available in this repository when this reference was written. Field types and optionality beyond the fields explicitly recognized by Cookbook remain subject to validation against exports from current Paprika versions.

## Container layers

| Extension | Container and content | Confidence |
| --- | --- | --- |
| `.paprikarecipe` | A gzip stream. Its decompressed payload is one UTF-8 JSON object representing a recipe. | Gzip + JSON is accepted by Cookbook's reader and reported in older export inspection. Paprika's official guide documents the family of formats but does not specify this single-file byte layout. |
| `.paprikarecipes` | A ZIP archive. Recipe entries are individual `.paprikarecipe` files; each entry's payload is itself gzip-compressed JSON. | ZIP containing gzipped recipe files is explicitly documented by Paprika and accepted by Cookbook's reader. |

The two layers in a collection are independent: unzip the collection, then gunzip each recipe entry, then decode its JSON as UTF-8. Cookbook reads ZIP entries stored directly or with DEFLATE, verifies sizes and CRCs, and then gunzips the recipe. The importer rejects encrypted entries, ZIP64, malformed checksums, and files over its limits (100 MiB input, 2,500 ZIP entries, 24 MiB per compressed recipe entry, 80 MiB combined compressed recipe entries). Other Paprika readers may accept more ZIP variants.

Cookbook writes collection entries using ZIP's stored method (no additional ZIP compression); the embedded recipe files are gzip streams. It uses UTF-8 JSON and UTF-8 ZIP entry names. Individual and collection output is written atomically before it is offered to the share sheet.

## Recipe object fields

The JSON object is case-sensitive. Paprika does not provide a full normative schema for `.paprikarecipe`; the older example and Cookbook's reader agree on several common names, but requiredness and types should be checked against current Paprika exports before building a general-purpose converter.

| Key | Paprika-style value observed/reported | Cookbook reader | Cookbook exporter |
| --- | --- | --- | --- |
| `uid` | String; older sample is UUID-shaped. Exact generation and validation rules are undocumented. | Required non-empty string; duplicate UIDs within a collection are rejected. | Existing imported Paprika UID is retained. Bundled recipes receive a deterministic UUID-formatted ID derived from their stable recipe ID. |
| `name` | String | Required non-empty string; becomes title. | Recipe title. |
| `ingredients` | String, typically one ingredient per line | Non-empty lines become ingredient rows. | One line per ingredient, with quantity followed by description. |
| `directions` | String with line or paragraph breaks | Split into ordered steps on blank lines. | Recipe steps joined as paragraphs; section headings are prefixed to their first step. |
| `servings` | Usually text/string | String, optional; retained as free text. | Servings text or empty string. |
| `categories` | Array of strings in observed examples | First non-empty string; defaults to `Imported`. | One-element array containing the app recipe category. |
| `description` | String or possibly null in exports; not fully documented | String; maps to the introduction. | Recipe introduction. |
| `notes` | String or possibly null in exports | String; blank-line-separated pieces become tips. | Recipe tips joined by blank lines. User notes/history are not exported. |
| `source` | String or possibly null | String; used as provenance name. | Provenance name or empty string. |
| `source_url` | String or possibly null | String; used as source reference. | Provenance reference or empty string. |
| `photo_data` | Base64 string reported in older exports; exact current requirements unknown | Accepts Base64 JPEG, PNG, or GIF bytes up to the per-entry limit. | Cover photo as Base64 JPEG, or empty string when unavailable. |
| `photo_large` | Seen by Cookbook reader as another possible Base64 photo field; details unknown | Fallback when `photo_data` is absent/unusable. | Not emitted. |

Paprika examples and the app reader also expose or may contain keys such as `rating`, `difficulty`, `prep_time`, `cook_time`, `total_time`, `nutritional_info`, `image_url`, `photo`, `photo_hash`, `photo_url`, `created`, `on_favorites`, and other app state. Cookbook currently ignores these keys and does not emit them. Their exact types, null conventions, photo filename relationship, hash calculation, and compatibility requirements are undocumented here. Unknown fields are ignored during Cookbook import, so those fields do not survive a Cookbook round trip.

Cookbook's recipe model has no direct Paprika equivalents for its structured ingredient metadata, labels, healthier options, menu relationships, cooking progress, device-local notes, dinner plans, or usage statistics. Those values are omitted. Export is a portable recipe copy, not a backup of all Cookbook app data.

## Photos and other media

The Cookbook reader checks `photo_data`, then `photo_large`, for Base64-encoded JPEG, PNG, or GIF bytes. If a valid image is found, it is saved as the imported recipe's cover. Cookbook export resolves the recipe's cover photo (or bundled thumbnail), converts it to JPEG, and writes only `photo_data`. A collection entry keeps the photo inside its gzipped JSON; no separate media file is added to the ZIP.

The older public export example reports `photo_data` as Base64 and also shows `photo`, `photo_hash`, and `image_url`, but does not establish how those fields relate across Paprika versions. Cookbook does not export external image URLs, secondary photos, step photos, or a Paprika photo hash. Only the current cover image is included. A recorded but unreadable cover causes export to fail rather than silently produce a partial collection.

## Cookbook-generated examples

The following compact object illustrates the current Cookbook exporter. Values are illustrative and the UID is shortened; a real exported UID is a complete stable UUID-formatted string. Recipe data is compressed as gzip bytes after UTF-8 JSON serialization.

```json
{
  "categories": ["Dinner"],
  "description": "A simple example.",
  "directions": "Warm the oven.\n\nBake until done.",
  "ingredients": "2 cups flour\n1 tsp salt",
  "name": "Example loaf",
  "notes": "Cool before slicing.",
  "photo_data": "",
  "servings": "1 loaf",
  "source": "Cookbook",
  "source_url": "",
  "uid": "C9067B12-8C7F-5A34-9C23-0123456789AB"
}
```

The matching collection layout is a ZIP listing similar to:

```text
Example loaf-C9067B12.paprikarecipe    # entry bytes are the gzip stream above
Second recipe-830AF611.paprikarecipe  # another gzip-compressed JSON object
```

The ZIP listing is illustrative; actual filenames are sanitized recipe titles plus a UID prefix to avoid collisions and unsafe paths. A single recipe share contains only the gzip bytes, not an outer ZIP. Cookbook has not validated these generated examples by round-tripping them through a Paprika app, so treat them as compatible-format output pending that check.

## Cookbook import behavior and round-trip limits

Cookbook accepts one gzip recipe or a ZIP with one or more `.paprikarecipe` entries. It parses the entire file before review, requires a non-empty `uid` and `name`, and rejects repeated UIDs in one collection. Import review previews recipes before persistence and lets users select collection entries. Duplicate Paprika UIDs and normalized recipe names are marked for review by default; users can explicitly select a duplicate to import an additional copy. Name matching ignores case and accents and collapses repeated whitespace. A match is never merged into or used to overwrite an existing recipe.

Imported records are stored locally in SwiftData and are not written into Markdown sources or the generated bundled catalog. Normal imports use `paprika:<lowercased UID>` IDs; a deliberately imported duplicate UID receives a unique local copy ID while preserving its Paprika UID. Each completed import run is saved in local history with imported and skipped counts, the skipped recipe names, a `Paprika file` label, and a unique date-and-run label applied to newly imported recipes. The import summary names both labels, links to the shared recipe list filtered to that run, and offers undo. Settings keeps concise recent run rows that open the same summary and undo controls. Deleted recipes, including bundled recipes, can be reviewed and restored individually.

Cookbook export uses the active combined library (bundled catalog plus non-deleted local Paprika imports), independent of browse search and filters. Imported recipes preserve their Paprika UID; bundled recipe UIDs are deterministic across repeated exports. Export does not alter either source collection. Fields not represented by Cookbook's `Recipe` model, and app-owned notes or history, are not retained in this interchange file.
