## User requirements

- As a home cook, I want to generate an image for a recipe that has no image from its recipe view, so that recipes without artwork can have a useful cover.
- As a home cook, I want a Settings action to generate images for all recipes that still have no image, so that I can fill those gaps in one resumable run.
- As a home cook, I want to choose the image-generation provider and its available model in Settings, so that I can use supported on-device generation or OpenAI with my own API key.
- As a home cook, I want generated images to reflect the complete recipe and remain available offline, so that the cover is relevant and survives relaunches.
- As a home cook, I want to review earlier cover images and restore one for a recipe, so that I can undo a generation or choose a better previous version.
- As a home cook, I want Settings to keep a history of bulk image-generation runs and show each run as the recipe thumbnail grid filtered to its results, so that I can review the batch and restore one image or undo the whole run.

Assumptions to confirm during implementation: “no image” means no saved cover photo and no bundled catalog thumbnail. Generation is opt-in from the recipe or Settings; regeneration is an explicit action and preserves the current cover until its replacement is successfully saved. OpenAI means the existing BYOK OpenAI integration. On-device generation may require an interactive system sheet for each recipe, so it may not be an unattended batch.

## Architecture and data model

Keep bundled recipe data immutable and generated images in the existing app-owned personal-data layer. Save each completed image as an app file under `UserFiles` and register it as that recipe’s cover with `RecipePhoto`. Retain prior saved image files and records as selectable versions instead of deleting them. Add SwiftData history records for each image-generation run and each recipe update in that run. A run records its time, provider/model, status, and counts; each recipe entry records the generated photo ID and a snapshot of the previous effective image (saved-photo ID, bundled asset name, or no image). This requires additive SwiftData model/container and migration work; keep existing recipe, photo, import, and dinner data readable. For regeneration, stage and validate the replacement first, then make it the cover; a failure or cancellation leaves the old cover intact. Saving each result and its history entry immediately makes the batch resumable.

The recipe’s image history must include saved imported, user-added, and generated photos, plus the current bundled thumbnail as a restorable source when applicable. Selecting an earlier version only changes which saved photo is marked as cover, or restores the bundled/no-image snapshot. Do not remove old image files when switching covers so an undo or later selection remains possible.

Settings keeps a durable list of bulk generation runs, including partial, interrupted, completed, and failed runs. Opening a run presents the existing primary recipe-browsing experience and thumbnail tiles filtered to recipes successfully updated in that run. Each run entry retains the before/after references needed for individual restore and “Undo all.” Undo only restores an entry while that run’s generated photo is still the current cover; if a later user action or run has replaced it, skip it and explain that it changed. Undo all reports restored and skipped counts and keeps the run history available.

Use one effective-cover resolver for recipe display and Paprika export: a saved cover photo takes precedence (regardless of whether it was imported, user-added, or generated); when none exists, use the bundled thumbnail. `PaprikaExporter.item` already follows this order for saved `RecipePhoto` records and bundled assets, so generated and imported images must be registered in that same path and covered by export checks. Both single-recipe `.paprikarecipe` and full-library `.paprikarecipes` exports must embed the effective image as `photo_data`; never omit it based on its origin.

Add image-generation preferences separate from dinner-planning preferences, so selecting an image provider does not silently change the dinner planner. Store bounded provider/model choices in app preferences and reuse the existing OpenAI Keychain credential; never put the key in UserDefaults, logs, recipe data, or exported files. Keep provider choice explicit and fail visibly on a missing key, unavailable on-device capability, network failure, or invalid image; do not fall back between providers.

Use the system-managed Image Playground presentation for on-device generation. Apple now deprecates the programmatic `ImageCreator` path and says it will stop working in iOS 27; the supported sheet returns the created image for the app to save. This means batch generation may need to present and complete the system UI once per recipe. The OpenAI path should use the documented image-generation API and the selected image-capable model. See [Apple Image Playground](https://developer.apple.com/documentation/imageplayground/) and the [OpenAI image-generation guide](https://developers.openai.com/api/docs/guides/image-generation).

## Basic test cases

- A recipe with neither a saved cover nor a bundled thumbnail offers image generation; after a successful generation, its cover appears in recipe detail and browse tiles, including after relaunch.
- A recipe with a saved photo or bundled thumbnail is excluded from the Settings batch; the detail view offers an explicit “Regenerate cover” action without replacing the current image until a new one is saved.
- Regenerating a bundled-only cover makes the new saved image the effective cover and preserves the bundled asset; failed or cancelled regeneration keeps the prior saved or bundled image visible.
- After a single-recipe regeneration, the user can open image history, preview a previous imported, user-added, generated, or bundled image, and restore it; the new image remains available as another version.
- Settings lists bulk runs by time and status. Opening one shows the main recipe thumbnail grid filtered to recipes generated in that run; opening a tile allows review and individual restore.
- “Undo all” for a run restores each unchanged recipe to the exact saved, bundled, or empty image state that preceded that run, reports entries skipped because their covers changed later, and can be repeated safely.
- Relaunching the app preserves run history, version choices, and the ability to restore previous covers; old image files remain readable while referenced by history.
- Single-recipe and full-library Paprika exports include the effective cover for a bundled-only recipe, an imported or user-added saved photo, and a generated saved photo. The export contains valid image data in `photo_data` for each case.
- Starting a batch with several eligible recipes processes them one at a time, saves each success immediately, reports progress, and skips saved results if interrupted and resumed.
- OpenAI selection with no saved key explains how to add one and sends no request. A rejected key, unavailable network, API error, or unusable image reports a recoverable error and leaves the recipe eligible for retry.
- On-device selection on an unsupported device or while Image Playground is unavailable explains the limitation and makes no cloud request. Cancelling a system sheet leaves that recipe eligible and does not discard earlier batch results.
- Switching the image provider does not alter the dinner-planning provider or its model. Removing the OpenAI key prevents cloud generation but does not affect on-device generation.
- The image-generation request contains one fixed instruction and the complete recipe text, including its title, passed directly as context to the selected image model. No text model rewrites, summarizes, or expands the prompt. The resulting image follows a mobile-friendly food-photo composition, avoids text/logos, and does not introduce major ingredients that conflict with the recipe.

## High-level implementation details

1. Define one eligibility rule over bundled recipes, imported recipes, saved `RecipePhoto` covers, and bundled thumbnail assets; use it both for the recipe-level action and Settings’ count/queue. Keep the UI truthful when no recipes qualify.
2. Define one static instruction used for every recipe and pass it, together with the complete recipe text including the title, directly to the selected image-generation model. Do not call a text LLM to author, rewrite, or summarize an image prompt. Example request:

   **Fixed image instruction:**

   > Create a realistic editorial cookbook photograph of the finished dish described in the recipe context. Treat the recipe title and complete recipe text as the source of truth; use its ingredients and preparation to determine what the finished dish looks like. Frame it as an appetizing close three-quarter view in a wide 4:3 composition, with natural light and enough detail to read well as a small mobile cookbook tile. Show the prepared dish, not raw ingredients. Do not add major ingredients that conflict with the recipe. No text, lettering, labels, logos, or watermark.

   **Recipe context (full recipe text passed directly, unchanged):**

   ```text
   # Chicken Piccata

   | Quantity | Ingredient |
   |---|---|
   | 2 | boneless skinless chicken breasts |
   |  | kosher salt |

   Slice chicken breasts in half horizontally and season with salt. Pound them flat. Let rest for 1 hour.

   | Quantity | Ingredient |
   |---|---|
   | 1 | cup flour |
   | 1 | tablespoon vegatable oil |

   Dry chicken with paper towels and dredge lightly in flour.

   Oil a saute pan and brown chicken on both sides over medium heat. Remove to a plate.

   | Quantity | Ingredient |
   |---|---|
   | 1 | shallot |
   | 1 | cup chicken stock |
   | 2 | lemons |
   | 2 | tablespoons capers |

   Mince shallot and saute in empty pan with salt. Add chicken stock to de-glaze, along with one sliced lemon.

   Reduce, and then add the juice of two lemons plus the capers. Reduce again.

   | Quantity | Ingredient |
   |---|---|
   | 3 | tablespoons butter |
   |  | parsley |

   Whisk in the cold butter one tablespoon at a time. Sauce the chicken and top with parsley.
   ```

   In implementation, supply the app’s complete recipe text without an LLM-generated intermediate description; this example shows the fixed instruction and direct recipe context as separate request inputs. The on-device adapter must map these inputs to the system-supported Image Playground UI and styles rather than implying an unavailable image model or style.
3. Add additive SwiftData models for image-generation runs and per-recipe before/after entries, register them in the model container, and verify existing-store migration. Snapshot previous cover identity before changing it and retain prior files/records; keep the run entry and produced `RecipePhoto` consistent when interrupted or retried.
4. Add a provider abstraction for OpenAI and on-device generation that passes the same fixed instruction and full recipe context directly to the image generator. Do not add a text-generation call or prompt-rewriting step. Add image validation/downsampling and atomic persistence into `UserFiles` plus `RecipePhoto`. Reuse the OpenAI Keychain helper, isolate image-specific model/provider preferences, and validate current API and OS availability during implementation.
5. Add an eligible-only generate action and an always-available explicit regenerate/history action to recipe detail, with progress, cancellation, version preview/selection, and failure-safe restore. Add Settings controls for provider/model, “Generate images for recipes without images,” and a persistent bulk-run history. Opening a run should reuse the primary `RecipeBrowserView`/`RecipeTile` grid filtered to that run’s generated recipes, with per-recipe and whole-run undo actions.
6. Ensure a successful save refreshes the existing cover-photo queries and leaves bundled catalog JSON and source recipes untouched. Make Paprika export resolve the same effective cover in both single-recipe and collection exports, regardless of whether the saved photo came from an import, user selection, or generation, falling back to the bundled thumbnail only when no saved cover exists. Update architecture, product, and design documentation to describe image history, run review/undo, local generated covers, export coverage, provider behavior, and the on-device interaction boundary.
7. Verify additive migration and relaunch persistence, provider selection and key isolation, generated file validity, no-image eligibility, explicit regeneration and failure-safe replacement, version selection, batch interruption/resume, individual and whole-run rollback (including a later-change skip), and Paprika export image data for each supported image origin. Then run the repository’s `make catalog-check` and `make sim-build`; treat simulator interaction and physical-device acceptance as separate evidence. Do not deploy automatically.

Material risk: Apple’s current on-device path is a system UI rather than a silent programmatic batch. Confirm the expected per-recipe interaction and target OS/device support before finalizing batch UX. OpenAI model identifiers and response formats can change; select and validate against the current official API documentation rather than assuming the dinner planner’s text model supports image generation.
