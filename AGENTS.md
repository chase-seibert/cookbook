# Project instructions

- Load the user-level instructions from `/Users/cseibert/.codex/AGENTS.md` before making changes.
- Prefer the project Makefile targets for common build and verification commands.
- Keep recipe source files and the generated cookbook outputs consistent when documentation or recipe content changes.
- Keep each recipe to exactly one page in the cookbook PDF. Condense prose and combine or remove redundant sections before reducing type size; preserve ingredient quantities, cooking temperatures, and food-safety cues.
- Format every recipe in one column. Do not use side-by-side or multi-column recipe layouts; fit content on one page by tightening prose and spacing while keeping ingredient groups and steps easy to scan.
- Keep ingredients in clearly named groups, with one ingredient per line and its quantity first. Give the quantity column enough width that fractions and ranges stay together, and keep each amount, unit, and ingredient description on the same line when possible. Use compact spacing without making the list hard to scan.
- After adding or modifying one recipe, generate and review only that recipe's PDF with `make recipe-pdf RECIPE=<recipe-id-or-source-slug>`. The target writes `build/recipe-pdf/<recipe-id>-preview.pdf` and fails if the recipe spans more than one page. For collections, use the individual stable recipe ID. Do not regenerate the full cookbook PDF for a single-recipe edit.
- Mobile app source lives in `ios/Cookbook/`; `scripts/generate_mobile_catalog.py` creates the bundled offline catalog from the authoritative LaTeX files. Run `make catalog` after recipe or generator changes and `make catalog-check` before app builds.
- Do not deploy the mobile app automatically after recipe, image, or catalog changes. Run `make phone-deploy` only when the user explicitly asks for deployment.
- Common workflows are `make sim-build`, `make sim-launch`, `make phone-build`, `make phone-install`, `make phone-launch`, and `make phone-deploy`.
