# Recipe Markdown Tools

These commands validate and convert one recipe file in the proposed
`cookbook-recipe/v1` Markdown format. LaTeX remains the authoritative recipe
source while the conversion and output comparisons are reviewed.

Set `RECIPE_MD` to the file to process:

```sh
make recipe-md-validate RECIPE_MD=recipes/turkey.md
make recipe-md-latex RECIPE_MD=recipes/turkey.md
make recipe-md-html RECIPE_MD=recipes/turkey.md
make recipe-md-import-sqlite RECIPE_MD=recipes/turkey.md
```

The validator checks front matter, supported format and layout values, title
and heading structure, labeled notes, ingredient and schedule tables, ordered
steps, and page-break syntax. Conversion commands validate before writing.

LaTeX fragments and HTML article fragments are written to
`build/markdown-conversion/<source-slug>.tex` and `.html`. They are fragments
for the existing cookbook LaTeX and HTML toolchains, not standalone documents.
The `compact` layout preset emits the reviewed Panko Mahi-Mahi formatting
macros in generated LaTeX and a layout class in HTML.

The checkout has no existing recipe SQLite database. The importer creates or
updates the reproducible build artifact `build/recipes.sqlite3` by default;
pass `RECIPE_DB=...` to select another path. Its schema version is 1 and stores
recipes, ordered content blocks, ingredient rows, and schedule rows. Importing
one file replaces only the row with that stable recipe ID. This database is a
derived artifact, not an editable source of truth.

The renderer intentionally preserves content order and text while applying
format-specific structure. The current LaTeX and HTML renderers have different
markup and spacing conventions, so compare recipe content separately from
typography and grouping.
