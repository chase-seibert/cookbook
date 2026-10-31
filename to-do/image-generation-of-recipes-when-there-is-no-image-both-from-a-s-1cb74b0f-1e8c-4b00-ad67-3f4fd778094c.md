## User requirements

- As a home cook, I want to generate an image for a recipe that has no image from its recipe view, so that recipes without artwork can have a useful cover.
- As a home cook, I want a Settings action to generate images for all recipes that still have no image, so that I can fill those gaps in one resumable run.
- As a home cook, I want to choose the image-generation provider and its available model in Settings, so that I can use supported on-device generation or OpenAI with my own API key.
- As a home cook, I want generated images to reflect the complete recipe and remain available offline, so that the cover is relevant and survives relaunches.

Assumptions to confirm during implementation: “no image” means no saved cover photo and no bundled catalog thumbnail; existing covers are never replaced. The batch action runs only after the user starts it. OpenAI means the existing BYOK OpenAI integration. On-device generation may require an interactive system sheet for each recipe, so it may not be an unattended batch.

## Architecture and data model

Keep bundled recipe data immutable and generated images in the existing app-owned personal-data layer. Save each completed image as an app file under `UserFiles` and register it as that recipe’s cover with the existing SwiftData `RecipePhoto` model. The model already stores recipe ID, file path, and cover status, so no schema migration is expected. Saving each result immediately makes the batch idempotent and resumable: later runs re-query eligibility and skip recipes that now have an image.

Add image-generation preferences separate from dinner-planning preferences, so selecting an image provider does not silently change the dinner planner. Store bounded provider/model choices in app preferences and reuse the existing OpenAI Keychain credential; never put the key in UserDefaults, logs, recipe data, or exported files. Keep provider choice explicit and fail visibly on a missing key, unavailable on-device capability, network failure, or invalid image; do not fall back between providers.

Use the system-managed Image Playground presentation for on-device generation. Apple now deprecates the programmatic `ImageCreator` path and says it will stop working in iOS 27; the supported sheet returns the created image for the app to save. This means batch generation may need to present and complete the system UI once per recipe. The OpenAI path should use the documented image-generation API and the selected image-capable model. See [Apple Image Playground](https://developer.apple.com/documentation/imageplayground/) and the [OpenAI image-generation guide](https://developers.openai.com/api/docs/guides/image-generation).

## Basic test cases

- A recipe with neither a saved cover nor a bundled thumbnail offers image generation; after a successful generation, its cover appears in recipe detail and browse tiles, including after relaunch.
- A recipe with a saved photo or bundled thumbnail is excluded from the Settings batch and is not overwritten by the single-recipe action.
- Starting a batch with several eligible recipes processes them one at a time, saves each success immediately, reports progress, and skips saved results if interrupted and resumed.
- OpenAI selection with no saved key explains how to add one and sends no request. A rejected key, unavailable network, API error, or unusable image reports a recoverable error and leaves the recipe eligible for retry.
- On-device selection on an unsupported device or while Image Playground is unavailable explains the limitation and makes no cloud request. Cancelling a system sheet leaves that recipe eligible and does not discard earlier batch results.
- Switching the image provider does not alter the dinner-planning provider or its model. Removing the OpenAI key prevents cloud generation but does not affect on-device generation.
- Recipe prompts include title, introduction, ingredients, full instructions, tips, and healthier options; the resulting image follows a mobile-friendly food-photo composition, avoids text/logos, and does not introduce major ingredients that conflict with the recipe.

## High-level implementation details

1. Define one eligibility rule over bundled recipes, imported recipes, saved `RecipePhoto` covers, and bundled thumbnail assets; use it both for the recipe-level action and Settings’ count/queue. Keep the UI truthful when no recipes qualify.
2. Add a recipe image prompt builder modeled on the prior thumbnail-generation session: use the complete recipe description as source of truth, with a close, realistic cookbook-food composition suited to a small landscape tile and constraints against unrelated ingredients, text, and watermarks.
3. Add a provider abstraction for OpenAI and on-device generation, image validation/downsampling, and atomic persistence into `UserFiles` plus `RecipePhoto`. Reuse the OpenAI Keychain helper, isolate image-specific model/provider preferences, and validate current API and OS availability during implementation.
4. Add a generate action to the recipe detail view only when eligible, with progress, cancellation, and actionable errors. Add Settings controls for provider/model and a “Generate images for recipes without images” action with eligible count, sequential progress, and stop/resume behavior.
5. Ensure a successful save refreshes the existing cover-photo queries and leaves bundled catalog JSON and source recipes untouched. Update the architecture/product/design documentation to describe local generated covers, provider behavior, and the on-device interaction boundary.
6. Verify provider selection and key isolation, generated file validity and relaunch persistence, no-overwrite eligibility, and batch interruption/resume. Then run the repository’s `make catalog-check` and `make sim-build`; treat simulator interaction and physical-device acceptance as separate evidence. Do not deploy automatically.

Material risk: Apple’s current on-device path is a system UI rather than a silent programmatic batch. Confirm the expected per-recipe interaction and target OS/device support before finalizing batch UX. OpenAI model identifiers and response formats can change; select and validate against the current official API documentation rather than assuming the dinner planner’s text model supports image generation.
