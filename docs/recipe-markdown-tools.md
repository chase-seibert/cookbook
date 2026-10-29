# Recipe Markdown Tools

These commands validate and convert recipe files in the authoritative
`cookbook-recipe/v1` Markdown format. Markdown is the recipe source of truth;
the iOS catalog, LaTeX, HTML, and SQLite files are generated outputs.

Set `RECIPE_MD` to the file to process:

```sh
make recipe-md-validate RECIPE_MD=recipes/turkey.md
make recipe-md-latex RECIPE_MD=recipes/turkey.md
make recipe-md-html RECIPE_MD=recipes/turkey.md
make recipe-md-import-sqlite RECIPE_MD=recipes/turkey.md
```

The validator checks front matter, supported format and layout values, title
and heading structure, labeled notes, ingredient and schedule tables, bare
paragraph steps, and page-break syntax. Conversion commands validate before
writing.

Run `make catalog` to generate the iOS bundle at
`ios/Cookbook/Resources/recipes.json`. Run `make latex` to generate the full
cookbook in `build/latex/`, including `Cookbook.tex`, `cookbook.sty`, and one
recipe fragment per Markdown file. Run `make html` to generate the full
`build/html/Cookbook.html`. `make catalog-check` checks that the bundled JSON
matches the Markdown source and its index. `make docker-pdf` compiles the
generated LaTeX cookbook.

The single-recipe LaTeX and HTML exporters write recipe fragments to
`build/latex/recipes/<source-slug>.tex` and
`build/markdown-conversion/<source-slug>.html`. The `compact` layout preset
emits the reviewed Panko Mahi-Mahi formatting macros in generated LaTeX and a
layout class in HTML.

The one-recipe SQLite importer creates or updates the reproducible build
artifact `build/recipes.sqlite3` by default; pass `RECIPE_DB=...` to select
another path. Its schema version is 1 and stores recipes, ordered content
blocks, ingredient rows, and schedule rows. Importing one file replaces only
the row with that stable recipe ID. This database is a derived artifact, not
an editable source of truth.

The HTML renderer keeps the published cookbook's plain browser-default layout:
a large title and source/date line, category headings with one recipe link per
line, a horizontal rule, then simple recipe headings, indented ingredient
lines, and paragraph breaks. It generates that presentation from Markdown
instead of parsing LaTeX.

The renderers preserve content order and text while applying format-specific
structure. Compare recipe content separately from typography and grouping.
