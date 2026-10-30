## User requirements

- As a user, I want to view descriptive tags or labels on a recipe, so that I can understand how it is categorized.
- As a user, I want to view how a recipe was obtained and its specific source when known, so that I can distinguish a website and URL from a Paprika import, manual entry, or another source.
- As a user, I want these tags and source details to be read-only in the app, so that recipe classification and provenance are supplied consistently by the catalog or recipe intake flow.

Assumptions: this targets the iOS Cookbook app. Users can see but cannot create, change, or remove tags, source types, or source references in the app. Catalog maintainers and recipe intake flows supply these values. Do not infer missing provenance; leave it unknown when no reliable source is available.

## Architecture and data model

The generated bundled catalog in `Catalog.swift` already carries curated `RecipeLabelGroup`, `RecipeLabel`, and per-recipe label assignments from `data/mobile/metadata.json`. Keep these as app-managed browse labels and extend the generated recipe data with structured provenance fields for source type and optional source name or URL. Do not add a user-editable annotation model for bundled recipes.

For bundled recipes, keep the human-authored label assignments and provenance in repository metadata, generate `ios/Cookbook/Resources/recipes.json` with `scripts/generate_mobile_catalog.py`, and expose the optional provenance fields through the read-only `Recipe` model. Keep source type distinct from its source reference: examples include Website plus a URL, Paprika import, Manual entry, personal cookbook repository, or Other. Existing recipes with unknown provenance remain valid and show no source detail.

For future app-owned imported or manually created recipe records, store tags and provenance with the authoritative recipe record in SwiftData, populated by the intake path. Present them through the same read-only recipe detail surface, without duplicating bundled catalog state or adding controls that mutate these fields. Preserve the existing curated-label filter behavior and older catalog decoding when optional provenance fields are absent. Add or migrate SwiftData schema only as required by the imported-recipe record implementation.

## Basic test cases

- A bundled recipe with curated tags displays those tags on its detail page; no add, edit, or remove control is available.
- A recipe with Website source type and a known URL displays both; Paprika import, manual entry, personal cookbook repository, and Other values display the source type and optional source text distinctly.
- A recipe with missing or unknown source metadata continues to load and displays no fabricated source or URL.
- Existing catalog JSON without provenance fields still decodes successfully, and generated catalog output includes newly authored metadata after `make catalog`.
- Existing category, search, and curated browse-label filtering continue to return the same results when provenance fields are absent or present.
- A future captured/imported recipe displays the source metadata supplied by its intake path, and repeated presentation does not allow the user to change it.

## High-level implementation details

1. Define the supported source-type values and optional source-reference shape. Keep the type separate from URL/name text, treat missing provenance as unknown, and do not make the fields user-editable.
2. Extend the repository metadata and mobile catalog generator to emit source type/reference for bundled recipes where the source is known. Add curated tags through the existing label definitions and assignments; do not hand-edit generated JSON.
3. Add backward-compatible optional provenance fields to the `Recipe` catalog model and render available tags and provenance read-only in `RecipeDetailView`. Preserve existing label filtering and recipe ordering.
4. Align planned website capture, Paprika import, and manual recipe intake so each writes the appropriate source type and known source reference directly to its durable recipe record. Leave values absent rather than guessing when import data does not establish the source.
5. Run `make catalog` and `make catalog-check`, then the relevant iOS build. Verify rendered detail states, catalog compatibility, browse filtering, and persistence for app-owned records separately; review SwiftData migration behavior when that record model is implemented.

Material risks: existing bundled recipes may not have enough evidence to populate external source details, so provenance should be added only from reviewed data. The generated catalog is immutable at runtime; user-specific editable metadata would require a separate future feature and is outside this plan.
