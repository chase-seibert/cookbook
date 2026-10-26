## User requirements

- As a user, I want a Vegetarian choice in the Protein filter instead of Beans & lentils, so that recipes without the listed meat or seafood proteins are easy to find.
- As a user, I want recipe filter choices listed alphabetically, so that every menu is predictable to scan.
- As a user, I want the More to browse choices folded into Meal Style, including baked goods, desserts, beverages, snacks, and cocktails, so that I can reach those recipes without a separate filter menu.
- As a user, I want Wine and other commonly leftover ingredients available in Ingredients, so that I can find recipes that use what I have on hand.

Assumptions: “Vegetarian” means a recipe whose reviewed labels include none of chicken, beef, pork, fish & seafood, or turkey; eggs and plant proteins remain eligible. This is a browse classification from catalog assignments, not a dietary guarantee. To remove More to browse without orphaning its existing coverage, fold its other labels (Breakfast, Condiment, Preserve, and Stock & broth) into Meal Style too. Curate additional leftover ingredients from actual catalog coverage; Wine is required.

## Architecture and data model

This uses the existing offline label pipeline: reviewed definitions and per-recipe assignments in `data/mobile/metadata.json`, generated `ios/Cookbook/Resources/recipes.json`, and menu rendering/filtering in `ios/Cookbook/CookbookApp.swift`. Replace the Beans & lentils Protein choice with a stable Vegetarian label and assign it to recipes with no reviewed meat/seafood Protein label. Keep Beans & lentils available as an ingredient where applicable. Move the existing More to browse labels into Meal Style and remove that group; add Wine and reviewed common-leftover ingredient labels to Ingredients.

The catalog already carries label IDs, group definitions, and ordering, so no persistence or schema migration is expected. Preserve stable recipe IDs, existing assignments, recipe ordering, and OR-within-group / AND-across-group filter behavior. Give each menu’s choices unique order values matching a case-insensitive alphabetical sort by display name.

## Basic test cases

- Protein choices are alphabetical, contain Vegetarian instead of Beans & lentils, and retain all other protein choices.
- Vegetarian matches recipes assigned no chicken, beef, pork, fish & seafood, or turkey label, including eligible egg- and bean-based recipes; recipes with any of those labels do not match.
- Meal Style contains the requested Baked goods, Desserts, Beverages, Snacks, and Cocktails choices, has no More to browse group, and retains the former group’s other browse labels under the stated assumption.
- Ingredients is alphabetical and includes Wine plus the reviewed common-leftover choices; selecting Wine returns only recipes assigned that label.
- Every menu remains alphabetically ordered after filtering; replacing or clearing a choice still updates results correctly, and category/search filters continue to combine with labels.
- Catalog validation accepts complete assignments and unique IDs/orders, and the generated catalog still decodes with stable recipe IDs and no duplicate results.

## High-level implementation details

1. Review current label definitions, recipe assignments, and generator checks in `data/mobile/metadata.json` and `scripts/generate_mobile_catalog.py`. Confirm the animal-protein label set used for the Vegetarian rule and inventory actual recipe coverage for wine and common leftover ingredients.
2. Update the reviewed taxonomy: replace the Protein beans-and-lentils option with Vegetarian; move all current browse-type labels into Meal Style and remove the More to browse group; add Wine and supported leftover ingredient labels. Renumber labels in each group to match alphabetical display-name order and preserve stable IDs except where replacing the beans-and-lentils choice.
3. Review every recipe assignment for Vegetarian against the stated exclusion rule and assign Wine/other ingredient labels only where recipe content supports them. Keep generated catalog files derived from metadata; do not hand-edit `recipes.json`.
4. Confirm `RecipeLabelFilter` and the existing menu rendering still apply one selection per group and combine groups as before. Add focused coverage in `tests/RecipeLabelTests.swift` for Vegetarian inclusion/exclusion, migrated Meal Style options, Wine matching, alphabetical choices, and unchanged combined filtering.
5. Regenerate and verify with `make catalog`, `make catalog-check`, and `make label-test`; inspect the Recipes filter menus in the app to confirm their displayed order and labels.

Risks and decisions: The Vegetarian rule depends on complete, accurate protein assignments; a missed meat or seafood assignment could produce a misleading match, so review the full catalog rather than infer from title alone. “Commonly have left over” does not specify a complete ingredient set; choose additions from actual recipe coverage and editorial review, with Wine as the required minimum.
