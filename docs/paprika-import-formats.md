# Paprika import formats

Cookbook imports Paprika recipe files from **Settings → Recipe imports** or from Paprika's share sheet using the **Cookbook** share extension. Choose **Send to Cookbook** in the extension, then open Cookbook to review before saving anything. iOS does not let a Share extension reliably launch its containing app, so shared files wait in a private App Group inbox until Cookbook is opened.

## Supported files

| Extension | Contents | Review |
| --- | --- | --- |
| `.paprikarecipe` | One gzip-compressed UTF-8 JSON recipe | Recipe preview with **Add Recipe** |
| `.paprikarecipes` | A ZIP archive containing one or more `.paprikarecipe` entries | Selectable recipe list with individual previews and **Add Selected** |

The archive reader accepts ZIP entries stored without compression or compressed with DEFLATE. It checks the ZIP entry size and CRC, then checks the embedded gzip stream while decoding its JSON. Encrypted entries and ZIP64 archives are not supported. The importer limits the input file to 100 MiB, each recipe entry to 24 MiB, the combined recipe entries to 80 MiB, and the archive to 2,500 entries.

## Review and duplicate behavior

The importer parses the complete file before presenting review. A collection starts with every new recipe selected. Existing Paprika UIDs are shown as already imported and cannot be selected again. **Select All** selects only new recipes; **Deselect All** clears the selection. Opening a recipe preview does not change its checkbox. Canceling, dismissing, or adding zero selected recipes leaves the stored recipe collection unchanged.

Confirming an import writes the selected recipes as device-local SwiftData records. A stable ID is formed from the Paprika UID, prefixed with `paprika:` so it cannot overlap bundled recipe IDs. Reimporting a UID skips it; the importer does not replace a recipe that may have acquired local notes, photos, usage history, or dinner references. Embedded JPEG, PNG, and GIF photos are copied into the app's Application Support directory and attached as the recipe cover.

## Field mapping

| Paprika field | Cookbook field |
| --- | --- |
| `uid` | Stable imported record ID and duplicate check |
| `name` | Recipe title; required |
| `categories` | First non-empty category, or `Imported` when absent |
| `description` | Recipe introduction |
| `ingredients` | One ingredient row per non-empty line; the original line is preserved as its name |
| `directions` | Ordered steps separated by blank lines |
| `notes` | Recipe tips/notes, separated by blank lines |
| `servings` | Recipe servings value |
| `source`, `source_url` | Internal Paprika provenance and source reference |
| `photo_data`, `photo_large` | Embedded cover image when it contains recognized image data |

Imported records carry the internal label ID `paprika-import` and Paprika provenance. The ID is not in the visible browse-label catalog, and the source marker is not shown as a badge. Paprika imports remain separate from the checked-in Markdown recipes and generated cookbook catalog.

## Errors

Unsupported or malformed archives, corrupt compression or JSON, duplicate UIDs within one file, and recipes without a usable title or UID stop the import before persistence. If photo or database persistence fails after confirmation, the selected recipes are not committed and any photos written for that attempt are removed.
