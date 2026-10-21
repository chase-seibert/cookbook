# Project instructions

- Load the user-level instructions from `/Users/cseibert/.codex/AGENTS.md` before making changes.
- Prefer the project Makefile targets for common build and verification commands.
- Keep recipe source files and the generated cookbook outputs consistent when documentation or recipe content changes.
- Mobile app source lives in `ios/Cookbook/`; `scripts/generate_mobile_catalog.py` creates the bundled offline catalog from the authoritative LaTeX files. Run `make catalog` after recipe or generator changes and `make catalog-check` before app builds.
- Common workflows are `make sim-build`, `make sim-launch`, `make phone-build`, `make phone-install`, `make phone-launch`, and `make phone-deploy`.
