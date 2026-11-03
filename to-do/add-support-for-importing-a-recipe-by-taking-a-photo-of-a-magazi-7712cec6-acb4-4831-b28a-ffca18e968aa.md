## User requirements

As a user, I want to take a photo of a magazine recipe or upload a photo I already have and have Cookbook extract its ingredients and instructions, so that I can add a printed recipe to my digital collection without retyping it.

As a user, I want to review and correct the extracted recipe before saving, so that recognition mistakes do not become authoritative recipe data.

Assumptions: the first version processes one selected image per import and uses the existing OpenAI key and configured model for image understanding. The image is extraction input and is not retained as the recipe's cover or as a source scan unless product scope later requires archival.

## Architecture and data model

Add a magazine-photo import entry point in Settings alongside the existing Safari and Paprika import options, offering both camera capture and photo-library selection. Reuse the existing camera capture wrapper where practical and use the system photo picker for uploads, while keeping the import flow separate from the current recipe-cover photo action.

Reuse the recipe draft, ingredient normalization, validation, editable review, and save conventions from `WebRecipeImport.swift`. Add an image extraction path using the Responses API's image input and the existing OpenAI model/key settings. Compress and bound the captured image before upload; request `store: false`, and reject incomplete or invalid extraction instead of filling gaps with guessed quantities or steps.

Persist the approved recipe locally as a normal `Recipe` payload in a dedicated `ImportedMagazineRecipe` SwiftData record with capture date and soft-delete metadata. Add a magazine-photo source type to `RecipeProvenance` so browsing and recipe detail can identify its origin. Register the new model in the app's model container and verify the additive SwiftData schema change against existing stores. The `Recipe` payload shape and bundled catalog need no change; the captured image remains transient.

## Basic test cases

- With a configured OpenAI key, capture a clear single-page recipe or select an existing image; verify both paths extract the title, ingredient groups and quantities, servings when present, and ordered instructions, then present an editable preview.
- Edit an extracted field and save; verify the edited values appear in the recipe library and detail view, with magazine-photo provenance and a capture timestamp.
- Capture a page with no recipe, an unreadable/partial recipe, or malformed extraction output; verify Cookbook reports the problem and does not save a recipe or silently invent missing content.
- Deny camera access, cancel capture, cancel photo selection, or use a device without a camera; verify the flow exits safely, still offers photo-library selection where available, and creates no record.
- Run without an OpenAI key or network, and exercise an oversized/unsupported image; verify a clear retryable error and no partial persistence.
- Relaunch with existing recipe data and a saved magazine import; verify existing Paprika/Safari records remain readable and the new import remains available.

## High-level implementation details

1. Extract shared draft-to-recipe construction and review behavior from the Safari flow only as needed, preserving its current behavior and ingredient normalization. Add image-specific request preparation, response parsing, validation, size limits, and actionable errors.
2. Add the Settings camera and photo-library actions with a dedicated import presentation state. Accept one image from either source, show extraction progress and retry/cancel controls, and reuse the established editable recipe preview before saving.
3. Add the magazine import SwiftData record and provenance case; register the model, assign the default category, save atomically, and include active/deleted magazine imports in library and Settings counts/history as appropriate. Leave the captured image out of persistent storage by default.
4. Verify extraction and validation with representative legible, ambiguous, partial, and non-recipe images; verify camera permission/cancellation and existing-store compatibility. Run `make sim-build` and `make phone-deploy` after implementation code changes, as required by the repository.

Risks and unresolved decisions: image quality, page curvature, glare, and multi-column layouts can reduce extraction accuracy; the review step must remain the user's confirmation point. Confirm whether future scope should support multiple pages or retain the original scan. OpenAI image-input limits and the selected model's vision support must be checked when implementing.
