# Recipe thumbnail generation

The Markdown recipe files remain authoritative. Generated thumbnails are derived,
offline app resources stored in `ios/Cookbook/Resources/Thumbnails/`; the
checkpoint manifest is `data/mobile/thumbnail-manifest.json`.

## Resumable workflow

Use Codex's built-in image-generation tool for one recipe at a time. Before
every image request, read the current Codex usage limits and use the primary
window only when its duration is 300 minutes. If usage is missing, older than
60 seconds, or the remaining percentage is 50 or lower, stop without starting
an image request. The next run can continue from the manifest.

After each fresh quota read, run `make thumbnail-queue
REMAINING_PERCENT=<live value> QUOTA_CHECKED_AT=<UTC ISO timestamp>`. The command
returns the next missing or stale recipe, a fingerprint, and a prompt
containing its title, introduction, ingredients, complete instructions, tips,
and healthier options. Generate that image, then run:

```sh
python3 scripts/recipe_thumbnails.py commit <recipe-id> <generated-image-path>
make catalog
```

Repeat from a fresh quota read before every next generation. `queue` without a
quota value, or at/below 50%, never emits a generation prompt. A commit crops
and resizes to 1024×768, encodes JPEG within 50–300 KB, validates the result,
atomically installs the asset, then atomically checkpoints the manifest. A
crash before the manifest update only leaves an untracked file, which is safely
eligible for retry. Identical, valid assets are skipped; a changed source,
prompt version, missing file, malformed image, or size violation is pending.

`make thumbnail-validate` checks all checkpointed image files and reports the
aggregate size. `make catalog-check` verifies that the bundled catalog matches
the Markdown sources and only references current manifest entries with existing
assets. No generation or network request runs inside the iOS app.
