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

# Printing

I use [Lulu.com](http://lulu.com)

```bash
Print Book: US Letter (8.5 x 11 in / 216 x 279 mm)
Standard Black & White, 60# White, Hardcover, Glossy Cover
```
