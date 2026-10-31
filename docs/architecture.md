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
  saved dinner timelines, cooking resume points, and persistent image-generation
  run and recipe-entry history. Photo bytes and PDF exports are stored under
  Application Support.
- `ImageGeneration.swift` builds one fixed food-photography instruction plus the
  complete recipe context, calls the OpenAI Images API directly or presents
  Apple's system Image Playground sheet, and saves validated JPEG covers as
  ordinary `RecipePhoto` records under `UserFiles/GeneratedRecipeImages`.
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

Generated and user-selected covers share the existing saved-photo path, which
has precedence over bundled thumbnails in recipe tiles and Paprika export.
Previous photo records and files are retained when switching covers. Each image
run stores per-recipe before/after photo identity so a run can be resumed,
reviewed, restored one recipe at a time, or undone while skipping covers changed
by a later action. Image provider and model preferences are separate from dinner
planning preferences; the cloud path reuses the OpenAI Keychain credential.
Image Playground is system presented and requires confirmation for each recipe,
so its bulk runs save progress incrementally and can be resumed after
cancellation or interruption. The sheet is attached only while an on-device
generation is being presented; it is seeded with a short finished-dish concept
and the complete recipe context as an extracted concept titled with the recipe.
The shared OpenAI credential is editable from general Settings, with a direct
link to OpenAI's API-key page; recipe image settings do not duplicate the key
editor. Main Settings orders the key editor before image generation and meal
planning. Completed bulk runs first present a cover-preview review screen, which
can continue into the Recipes browser filtered to that run.

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
