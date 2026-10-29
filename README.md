# Chase Seibert's Cookbook

Recipe content is maintained as Markdown in [`recipes/`](recipes/), using the
format in [`docs/recipe-markdown-format.md`](docs/recipe-markdown-format.md).
The order of categories and recipes is in [`recipes/index.json`](recipes/index.json).
The iOS catalog, LaTeX cookbook, PDF, and HTML cookbook are generated outputs.

- [Published PDF](https://chase-cookbook.s3.us-west-2.amazonaws.com/cookbook.pdf)
- [Published HTML](https://chase-cookbook.s3.us-west-2.amazonaws.com/cookbook.html)

## Generate cookbook outputs

```bash
make catalog          # iOS bundled catalog: ios/Cookbook/Resources/recipes.json
make catalog-check    # verify the bundled catalog matches Markdown
make latex            # LaTeX files under build/latex/
make docker-pdf       # build/latex/Cookbook.pdf
make html             # build/html/Cookbook.html
```

The LaTeX build uses the repository Docker image so it does not depend on a
local TeX installation. For a one-recipe preview, use the stable recipe ID or
Markdown source slug:

```bash
make recipe-pdf RECIPE=bread
```

The preview is written to `build/recipe-pdf/` and checks the one-page recipe
limit. Keep recipe layouts in one column and preserve ingredient amounts,
temperatures, and food-safety instructions.

## iPhone app

The native SwiftUI app lives in `ios/`. Its offline recipe catalog is generated
from the Markdown recipe files and cookbook index; do not edit
`ios/Cookbook/Resources/recipes.json` by hand.

```bash
make catalog
make catalog-check
make sim-build
make sim-launch
```

See [the mobile setup guide](docs/setup-install.md) and
[the app architecture](docs/architecture.md).

## Printing

I use [Lulu.com](http://lulu.com).

```text
Print Book: US Letter (8.5 x 11 in / 216 x 279 mm)
Standard Black & White, 60# White, Hardcover, Glossy Cover
```
