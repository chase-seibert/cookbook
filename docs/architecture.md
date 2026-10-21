# Mobile app architecture

## Source and generated data

LaTeX files and `Cookbook.tex` remain the authoritative recipe source. The
standard-library Python generator in `scripts/generate_mobile_catalog.py`
parses the cookbook index, recipe sections, ingredients, prose, tips, and
healthier options. `data/mobile/metadata.json` stores stable file IDs, files
whose section headings are collections rather than recipes, grocery staple and
exclusion rules, per-ingredient overrides, and optional per-step ingredient
assignments. A normal source file produces one recipe; designated collections
such as Cocktails produce one recipe for each subsection and show the parent as
a list heading. The catalog hashes source sections and keeps original
instruction text. `make catalog-check` rebuilds in memory and rejects stale
output.

The catalog preserves chapter order from `Cookbook.tex`. Subsections inside a
recipe remain instruction headings, so “Carving” and “Secret Sauce” do not
become separate recipes. Each instruction paragraph is assigned the nearest
preceding ingredient block. Recipes that reuse ingredients across components
need reviewed `stepIngredientIDs` metadata.

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
