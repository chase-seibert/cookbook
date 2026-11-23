# Task #409: Name AI-parsed recipes for the dish

## User requirements

- As a user, I want an AI-parsed recipe to use the name of the dish, so that my recipe library identifies what I will cook rather than the article or website that published it.
- As a user, I want recipe source information to remain available separately, so that a dish-focused recipe name does not lose its origin.
- Assumption: this applies to both AI extraction from a Safari webpage and AI extraction from a magazine photo, since both flows populate the saved recipe title from an AI draft. Keep the existing review-and-edit step.

## Architecture and data model

The primary change should be to the extraction prompts: guide the model to summarize/name the recipe by the dish represented by its ingredients and instructions. In the webpage flow, explicitly treat the captured page title and URL as context rather than a preferred recipe name; in the magazine-photo flow, prefer the printed recipe heading when it names the dish. Keep the existing draft title field and editable review flow. Add title cleanup only if prompt-focused changes leave a demonstrated gap.

No material data-model, persistence, schema, or migration change is required: the recipe title is already stored in the `Recipe` payload, and web source URL and import provenance are stored separately. Preserve the editable title in each import review screen.

## Basic test cases

- Import a page titled “The Best Weeknight Dinner Ideas | Example Site” whose recipe heading is “Lemon Garlic Chicken”; the review and saved recipe title should be “Lemon Garlic Chicken,” while the page source remains associated with the import.
- Import a page whose page title already names the dish; the extracted dish name should remain natural and should not gain a site or article suffix.
- Import a magazine photo with a visible dish heading; the review title should use that heading rather than nearby publication or feature text.
- Import a recipe whose source has no clear dish heading; the proposed title should be a concise name grounded in the recipe content, without inventing unsupported specifics. The user can still edit it before saving.
- Verify the title continues through preview, save, recipe list/search, and reopening the imported recipe; invalid or empty AI titles should continue to follow the existing validation/error path.

## High-level implementation details

1. Review `WebRecipeExtractor.extract` in `ios/Cookbook/WebRecipeImport.swift` and `MagazineRecipeExtractor.extract` in `ios/Cookbook/MagazineRecipeImport.swift`, focusing on the prompts that produce `WebRecipeImportDraft.title`.
2. Revise prompt wording to ask for a concise dish name based on the extracted recipe, prefer a recipe-specific heading when present, and ignore site/publication branding or article framing when choosing the saved title. Keep the rest of the extraction instructions and editable review behavior intact.
3. Add or update focused checks for prompt construction and representative title outcomes without requiring live OpenAI requests. Include article-title-versus-dish-title and missing-heading cases.
4. Consider title normalization or fallback logic only if focused examples show that clearer prompts do not solve the issue; avoid generic site-name stripping that could damage valid dish names.
5. Run relevant import checks, then `make catalog-check`, `make sim-build`, and `make phone-deploy` after Swift changes. Review web and magazine import previews through an available UI path if practical.

Risk: a page can contain multiple recipe-related headings or branding mixed into the recipe heading. Prefer the heading attached to the extracted ingredient/instruction set, and retain the current editable review as the final correction point.
