# Chase Seibert's Cookbook

This is a collection of recipes in LaTeX format.

- [PDF version](https://chase-cookbook.s3.us-west-2.amazonaws.com/cookbook.pdf)
- [HTML version](https://chase-cookbook.s3.us-west-2.amazonaws.com/cookbook.html)

# Compiling 

See the GitHub Actions tab for this project and the related YAML files under `.github/workflows`. 

Compiling PDF for local development: 

```bash
pdflatex Cookbook.tex
open Cookbook.pdf
```

Compiling HTML for local development: 

```bash
./run_html.py --index Cookbook.tex > Cookbook.html
open Cookbook.html
```

## Docker

The PDF Docker flow uses the same full TeX Live image as the GitHub Actions
workflow (`xu-cheng/latex-action@v2`). This keeps local compilation isolated
from macOS LaTeX installations:

```bash
make docker-pdf
make docker-html
```

On Apple Silicon, the PDF image runs as `linux/amd64`, matching the GitHub
Actions runner. The first PDF build downloads the TeX Live image and may take
some time.

Recipe notes can use `\tip{...}` for general tips or `\healthierOption{...}` for healthier alternatives.

## iPhone app

The `ios/` directory contains a native SwiftUI app and an offline recipe catalog
generated from the LaTeX sources. Recipe files remain authoritative; do not edit
`ios/Cookbook/Resources/recipes.json` by hand.

```bash
make catalog
make catalog-check
make sim-build
make sim-launch
```

See [the mobile setup guide](docs/setup-install.md) and [the app architecture](docs/architecture.md).

# Printing

I use [Lulu.com](http://lulu.com)

```bash
Print Book: US Letter (8.5 x 11 in / 216 x 279 mm)
Standard Black & White, 60# White, Hardcover, Glossy Cover
```
