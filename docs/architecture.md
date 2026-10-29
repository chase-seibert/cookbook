# Mobile app architecture

## Source and generated data

Markdown files in `recipes/` are the authoritative recipe source. The
standard-library Python generator in `scripts/generate_mobile_catalog.py`
parses the versioned recipe format into the offline iOS catalog. The ordered
category and recipe index is `recipes/index.json`. `data/mobile/metadata.json`
stores grocery staple and exclusion rules, per-ingredient overrides, reviewed
per-step ingredient assignments, labels, and menu copy. A normal source file
produces one app recipe; collections such as Cocktails produce one app recipe
per H2 component and show the collection title as the parent. The catalog uses
Markdown source filenames and hashes canonical parsed content. `make
catalog-check` rebuilds in memory and rejects stale output.

`make latex` generates per-file LaTeX fragments and a complete LaTeX index in
`build/latex/`. `make html` generates the complete standalone HTML cookbook in
`build/html/Cookbook.html`. Both are derived outputs; do not edit them by hand.
Subsections inside a normal recipe remain instruction headings. In a collection
they identify the contained recipes. Each instruction step receives the
nearest preceding ingredient group's IDs unless reviewed `stepIngredientIDs`
metadata provides a more precise mapping.

## App layers

- `Catalog.swift` decodes the immutable bundled catalog.
- `CookbookApp.swift` owns tab navigation and the SwiftData container.
- `PersonalData.swift` stores notes, photo metadata, scheduled recipe dates,
  saved dinner timelines, and cooking resume points. Photo bytes and PDF exports are stored
  under Application Support.
- `CookingAndGroceries.swift` presents one-step cooking mode and a Reminders
  ingredient review before writing quantity-free reminders. Grocery labels
  strip package and measurement wording, ignore plain water, and classify
  common spices, oils, and Better Than Bouillon as pantry staples.
- `NotesAndPrint.swift` handles free-form notes and paginated PDF output.
- `SettingsAndDinner.swift` stores preferences and Keychain credentials, exports
  timestamped notes, generates AI estimates, and saves/duplicates dinner
  timelines.

Notes, photos, and timelines are app-owned data and are not overwritten when a
new bundled catalog is installed. Notes export currently provides separate
timestamped JSON and Markdown files. The first implementation does not yet
provide the planned migration/export archive for all personal data.

## Known implementation gaps

Ingredient-to-step mappings still need metadata review for reused ingredients.
AlarmKit timers and a timer widget are not implemented. Photos can be
selected or captured and are copied to app-owned storage; the optional Photos
album flow is not implemented. OpenAI scheduling uses Structured Outputs and
validates that each selected step is returned exactly once, then applies a
sequential one-cook work-back schedule. The timeline can be edited, saved,
duplicated for next year, and printed as a one-page two-column checklist when it
fits. Scheduling does not model overlapping passive work, resource conflicts,
dependency graphs, duration edits, multi-day preparation activities, or
equipment feasibility. The on-device provider is currently an explicit
unavailable state and never falls back to cloud. Manual drafts use 15-minute
estimates for untimed steps. Ingredient-to-step mappings and component
subsection relationships still need review; grocery staple classification has
an editable starter list, and aliases still need review.
