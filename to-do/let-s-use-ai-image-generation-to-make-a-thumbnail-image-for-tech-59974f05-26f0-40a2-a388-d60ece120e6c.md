# AI-generated recipe thumbnails — task #243 plan

## User requirements

- As a home cook, I want each recipe to have a useful thumbnail generated from its full recipe description, so that picture-first browsing reflects what the recipe actually involves rather than only its title.
- As a maintainer, I want each batch run to create only missing or stale thumbnails and resume from saved progress, so that retries do not duplicate work and later runs can continue through the catalog.
- As a maintainer, I want a batch run to continue only while more than 50% remains in the current Codex five-hour quota window, so that image generation yields before the requested quota boundary and can resume later.
- As a home cook, I want thumbnail assets sized and compressed for the mobile browse grid, so that they remain clear without adding excessive app download size.

Assumption: “tech recipe” in the task title means “each recipe,” consistent with the request to resume and process more later. Plan for the catalog’s recipes as a batch; confirm this interpretation during implementation if needed. The app must continue browsing offline, and a user-selected cover photo should continue to take precedence over a generated thumbnail.

## Architecture and data model

Keep LaTeX recipe files authoritative and generate image files as build-time repository assets; do not call an image service from the iOS app. Add a resumable batch-generation script and a tracked manifest keyed by stable recipe ID. Record a canonical source/prompt fingerprint and completed asset path so reruns skip a valid image for unchanged recipe content, while changed content or a missing/corrupt output becomes eligible for regeneration. Write generated output to a temporary file, validate it, then atomically move it into place and update the manifest so interruption cannot mark a partial image complete.

Generate prompts from the complete catalog description (title, introduction, ingredients, instructions, tips, and healthier options where present), not the title alone. Check the Codex five-hour quota before each generation and stop before starting another request once remaining quota is at or below 50%. The quota source and whether this environment exposes a supported, reliable remaining-quota value are unresolved feasibility questions; if unavailable or unknown, stop with a visible resumable status rather than guessing or continuing past the boundary.

Extend catalog generation/model data with an optional stable thumbnail asset key, backed by the manifest, and bundle the corresponding compressed images for offline use. Preserve recipe IDs and existing user data; no SwiftData migration is expected. Update the browse tile fallback order to user-selected cover photo, generated thumbnail, then the existing neutral placeholder. Use a mobile-appropriate landscape thumbnail (proposed 4:3, 1024×768 JPEG, with a reviewed target size band around 100–300 KB per image); confirm format and size targets against actual rendering and catalog-wide app size during implementation.

## Basic test cases

- Run the batch with quota above 50% and several recipes pending: it generates valid thumbnails and records completion for each asset.
- Run again with unchanged sources and valid assets: it generates nothing and leaves manifest entries and file contents unchanged.
- Interrupt after an image is generated but before later recipes finish, then resume: completed outputs are retained and only remaining or invalid assets are processed.
- Change a recipe description or prompt version: only that recipe’s fingerprint becomes stale and its thumbnail is regenerated.
- Begin at exactly 50% remaining, below 50%, or with unavailable quota data: no new image request starts; progress remains resumable with a clear stop reason.
- Simulate a failed generation, truncated image, or invalid format: no partial output is committed as complete, and a later run can retry that recipe.
- Browse with a generated image, with a user cover photo, and with neither: generated imagery appears only when no personal cover exists; the existing placeholder remains the final fallback.
- Validate representative images at mobile tile size and verify dimensions, decodeability, per-file size bounds, and acceptable aggregate app-bundle growth.

## High-level implementation details

1. Inspect the supported Codex quota/usage interface and the available image-generation invocation path. Define the quota value as remaining percentage in the active five-hour window, check it before every image request, and make missing/stale quota data a safe stop. Confirm the intended set of recipes and the practical image size/format target.
2. Add a batch script that reads the generated catalog, creates a full-description prompt per stable recipe ID, fingerprints all prompt inputs and generation settings, and reads/writes a manifest checkpoint. Sort work deterministically, skip current valid assets, and commit each successful image and manifest update atomically; surface failures and a resumable stop summary.
3. Add image validation and optimization for the agreed dimensions/format/size band. Keep image outputs separate from personal photos and recipe source, and avoid regenerating assets when a run is repeated without relevant source or settings changes.
4. Connect manifest asset keys through `scripts/generate_mobile_catalog.py` and `ios/Cookbook/Catalog.swift`; include assets in the iOS target and use them in `RecipeTile` only after checking for a user cover photo. Preserve offline loading and existing recipe identity.
5. Update relevant architecture/product documentation and Makefile entry points for generation and validation. Verify idempotence, interruption/resume, quota boundary behavior, stale-source handling, asset size limits, `make catalog-check`, and simulator browse behavior. Review representative grid screenshots and aggregate bundle size; a successful build alone does not establish visual quality.
