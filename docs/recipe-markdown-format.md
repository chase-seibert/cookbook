# Recipe Markdown Format

## Status

This document specifies the proposed human-editable recipe format for the
cookbook. An initial Markdown file has been created for each of the 68 indexed
LaTeX recipe sources, and the ordered content model round-trips through the
Markdown representation for all 68. LaTeX remains authoritative until the
conversion and generated-output comparisons are reviewed and accepted. The
five-recipe prototype established semantic reversibility for long recipes;
this format removes the prototype's comment markers and raw-LaTeX layout
fence.

## Goals

- Make each recipe readable and reviewable as ordinary Markdown in Git.
- Preserve ingredient amounts, ingredient-group boundaries, instruction order,
  notes, temperatures, safety cues, section order, and stable recipe identity.
- Generate LaTeX/PDF, HTML, SQLite when needed, and the mobile catalog from the
  same validated recipe data.
- Use Markdown syntax and explicit metadata rather than cookbook-specific
  comment markers or embedded LaTeX.
- Support semantic round-tripping. Generated LaTeX may normalize whitespace and
  equivalent notation, so byte-for-byte reproduction is not required.

## Files and identity

Store one Markdown file per existing LaTeX source at
`recipes/<source-slug>.md`. Use UTF-8. Keep the source slug in the filename and
the stable recipe ID in YAML front matter. The H1 is the display title. Do not
derive IDs from titles, since titles can change.

```markdown
---
format: cookbook-recipe/v1
id: cinnamon_bun
layout: default
---

# Julie's Cinnamon Rolls
```

`format` and `id` are required; `id` is immutable after assignment. `kind` is
optional and defaults to `recipe`. Use `kind: collection` when one source file
contains multiple separately titled recipes or recipe components. `layout`
is optional and must name a supported renderer preset; omit it for the default
layout. Initial presets are `default` and `compact`. Recipe-specific TeX
commands must be represented by a reviewed preset or a new typed field, not
copied into Markdown.

The per-file validator, LaTeX and HTML exporters, SQLite importer, and Makefile
commands are documented in [Recipe Markdown Tools](recipe-markdown-tools.md).

Chapter order belongs in a separate, version-controlled cookbook index.
Existing source files that contain multiple separately titled recipes remain
one same-named Markdown file with `kind: collection`; their H2 headings retain
the source's subsection order. A regular recipe uses H2 headings for its
sections. A collection uses its H1 for the collection title and H2 headings
for its contained recipes or components. Do not split existing collections
into files as part of a source-format conversion.

## Body syntax

### Recipe title and sections

Use exactly one H1 for the recipe or collection title. Use H2 headings for
ordered recipe sections, or for contained recipes/components in a collection.
Preserve heading order. Do not use heading levels to imply an ingredient
group; ingredient tables identify those groups.

### Introductions and notes

Use a labeled blockquote for an introduction, tip, or healthier option. The
label is part of the format and is removed or restyled by output renderers.
Continue multi-paragraph notes as one blockquote, with the label only on its
first paragraph.

```markdown
> **Introduction:** Makes about 16 rolls. You can make these the night before;
> cover them airtight.

> **Tip:** Use a larger baking dish for quicker cooking and more browning.

> **Healthier option:** Use the listed lower-fat alternative.
```

An unlabeled blockquote is invalid. This keeps notes distinct from instruction
steps without parser comments.

### Ingredient groups

Represent each ingredient group as a Markdown table with the exact headers
`Quantity` and `Ingredient`, in that order. Each table is one group. Keep tables
in their original position among the instructions; do not move all ingredients
to the start of a recipe. Use a blank quantity cell for ingredients whose
source has no amount. Preserve the quantity wording as written instead of
splitting or recalculating its amount and unit.

```markdown
| Quantity | Ingredient |
|---|---|
| 2 cups | milk |
| 16 tablespoons | butter |
| ¾ cup | sugar |
|  | salt |
```

Escape a literal pipe in a cell as `\\|`. A table with any other header is not
an ingredient group. Legacy `ingredients` and `ingredientsLeft` blocks that
contain ordinary ingredient rows both use this table form.

### Schedules

Use a table with `Time` and `Task` headers for a recipe timeline. This
distinguishes schedules from ingredient groups without an extra marker. When
converting a legacy `ingredientsLeft` block, rows that begin with a clock time
(for example, `9:00`) become `Time` and `Task` cells. Other such blocks remain
ingredient tables.

```markdown
| Time | Task |
|---|---|
| 9:00 | Start green bean base |
| 10:00 | Prepare stuffing |
| 12:00 | Put turkey in at 425° |
```

### Instructions

Use an ordered list for instructions. Each list item is one ordered step; wrap
long steps onto following indented lines. Use `1.` for each item so inserting a
step does not require renumbering later lines. Keep the recipe's original
wording and safety cues. Tables and notes may appear between instruction lists
to preserve the original sequence of ingredient groups and steps.

```markdown
1. Heat the oven to 350°.
1. Add the apples, onions, and water to the roasting pan.
1. Roast until the ham reaches 140°.
```

### Page breaks

Preserve an intentional page break with this standalone HTML element between
sections:

```html
<div class="page-break"></div>
```

The HTML renderer should keep this element visually empty. The print/PDF
renderer maps it to a page break. Do not add it merely to control current
pagination; use it only where the source has an intentional section break.

### Inline notation

Write degree values with `°` and common fractions with Unicode fraction
characters (`⅛`, `⅓`, `½`, `⅔`, `¼`, `¾`, and related supported values). The
LaTeX exporter maps these to the cookbook's degree and fraction macros. Preserve
ranges and mixed quantities, for example `1¾–2 lb`, as one quantity cell.
Escape Markdown syntax characters where required by CommonMark. Do not use
LaTeX commands for ordinary inline notation.

## Metadata outside recipe prose

Keep stable IDs, collection membership, renderer presets, and other typed
recipe-level fields in front matter or the cookbook index. Keep app-specific
cross-references, such as reviewed step-to-ingredient assignments, in a
version-controlled text metadata file keyed by stable recipe ID until those
relationships have a clear Markdown representation. Do not hide structured
data in HTML comments.

## Validation and round-trip requirements

- Reject duplicate/missing IDs, unsupported format versions, unknown layout
  presets, malformed tables, unlabeled blockquotes, invalid heading structure,
  and unsupported constructs with file and line diagnostics.
- Do not silently retain unknown LaTeX commands in prose or discard them during
  conversion. Add an explicit Markdown representation and exporter support
  before accepting each unsupported construct.
- Parse each Markdown recipe into an ordered content model. Verify that
  Markdown-to-LaTeX-to-model produces the same content, quantities, groups,
  notes, sections, and sequence as the source model.
- Keep formatting normalization separate from content comparison. Verify
  recipe-by-recipe HTML text/order/links and PDF text/layout against pinned
  baseline outputs before switching the source of truth.
- Confirm a clean checkout can generate every output deterministically from the
  Markdown files, cookbook index, and reviewed text metadata alone.

## Example with ordered groups and steps

```markdown
---
format: cookbook-recipe/v1
id: cinnamon_bun
---

# Julie's Cinnamon Rolls

> **Introduction:** Makes about 16 rolls. You can make these the night before;
> cover them airtight.

| Quantity | Ingredient |
|---|---|
| 2 cups | milk |
| 16 tablespoons | butter |
| 1 tablespoon | shortening |
| ¾ cup | sugar |

1. Combine and bring to 185° over medium heat.

| Quantity | Ingredient |
|---|---|
| ½ cup | warm water |
| 3 tablespoons | yeast (3 packets) |
| 2 tablespoons | sugar |

1. Combine and let rise until doubled in size, about 30 minutes.

> **Tip:** The rolls can be held overnight or frozen before the final rise.
```
