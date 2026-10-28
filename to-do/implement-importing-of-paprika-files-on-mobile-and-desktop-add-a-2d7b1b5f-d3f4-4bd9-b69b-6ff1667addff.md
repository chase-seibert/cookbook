## User requirements

- As a user, I want to preview a single Paprika recipe before adding it, so that I can confirm what will be saved.
- As a user, I want to preview every recipe in a multi-recipe Paprika export and select recipes with checkboxes, so that only the recipes I choose are added to my database.
- As a user, I want imported recipes marked internally as Paprika imports, so that the app can identify their origin without adding a visible browse label.

Assumptions to confirm during implementation: the multi-recipe preview initially selects all successfully parsed recipes and lets me deselect any before adding; the same Paprika `uid` should not silently create a duplicate; and embedded recipe photos should be retained when available. The supplied examples cover a one-recipe export and a 220-recipe export.

## Architecture and data model

The bundled catalog in `Catalog.swift` is generated and immutable, while personal data is stored in SwiftData. Add a Paprika reader that accepts the outer ZIP export, reads each `.paprikarecipe` entry (gzip-compressed JSON), validates and converts supported fields into the app’s recipe representation, and finishes parsing before showing the review. Map title, description, ingredient lines, direction steps, notes, source, category, servings, and available photo data. Preserve stable source identity using Paprika `uid` and an internal Paprika-origin marker.

Persist imported records separately from the generated catalog in the app’s durable store, and have recipe browsing, search, details, and downstream recipe actions read a combined recipe collection. Keep imported IDs distinct from bundled recipe IDs so notes, photos, cooking progress, and dinner plans remain associated with the correct recipe. Add the new SwiftData model to the container and verify opening an existing store; use a versioned migration only if the chosen schema change requires one.

The import flow has two review states. For one recipe, show its recipe details and an explicit Add Recipe action; cancellation or dismissal leaves the database unchanged. For a collection, show a selectable recipe list with per-recipe checkboxes, selection counts, and Select All / Deselect All controls; allow opening an individual preview from that list. Add Selected commits only checked recipes, and is unavailable when none are selected. Persist only after confirmation, ideally as one transaction, and report success or failure without leaving a partially imported selection.

## Basic test cases

- Open the supplied single-recipe export: show its title and mapped recipe contents in a preview; confirm adds one recipe, while cancel or dismissal adds none.
- Open the supplied collection export: show all 220 parsed recipes in a selectable list; deselect several, add the rest, and verify that only checked recipes enter the database.
- Open an individual recipe from the collection preview and return to the same list with its checkbox selection preserved.
- Use Select All and Deselect All, verify the selected count, and verify Add Selected cannot add anything when the selection is empty.
- Reimport a previously imported Paprika `uid`: apply the chosen duplicate policy consistently and report added, skipped, or updated counts.
- Choose a corrupt archive, malformed gzip/JSON entry, empty export, or recipe missing a usable title: show a useful error and leave the database unchanged.
- Relaunch after importing and verify imported recipes remain available while existing notes, photos, usage counts, dinner data, and bundled recipes remain intact.

## High-level implementation details

1. Confirm the duplicate policy and checklist default selection behavior. Inspect representative Paprika records and archive limits; avoid checking the full 57 MB sample export into the repository, and create small fixtures for parser and preview tests.
2. Define a platform-independent Paprika import model and ZIP/gzip/JSON reader. Validate archive structure, required fields, encodings, duplicate UIDs, and optional image payloads; return parsed recipes without writing them.
3. Add a preview model and selection state. Present a detail preview and explicit confirmation for a single recipe; present a checkbox list, per-recipe preview, selection controls, and Add Selected confirmation for collections.
4. Add durable imported-recipe persistence and an import service that commits only the confirmed selection, associates optional photos with collision-safe paths, applies the internal origin marker, and handles duplicates without silently overwriting local edits.
5. Merge imported recipes into the existing browse, search, detail, and recipe-action data flow without exposing the internal marker as a normal label. Verify parser and selection behavior with single and multi-entry fixtures, cancellation, zero selection, corrupt inputs, repeated imports, and an existing SwiftData store. Run relevant Makefile catalog checks and app builds after implementation; assess build and on-device interaction as separate evidence.
