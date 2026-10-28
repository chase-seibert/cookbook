## User requirements

- As a home cook, I want to open a link or browse for a recipe in the iPhone's Safari browser, so that I can use Safari's normal website rendering, sign-in, cookies, and user-agent behavior.
- As a home cook, I want to invoke Cookbook from Safari on the recipe page and send its webpage content to an LLM, so that the LLM can extract the actual recipe without a separate automated page fetch.
- As a home cook, I want to review and correct the extracted recipe before saving, so that extraction errors do not become my recipe.
- As a home cook, I want the saved recipe and its source link to remain available after the website changes or goes offline, so that I can cook from a durable local copy.
- Assume this plan targets the iOS Cookbook app. Desktop capture remains out of scope unless confirmed separately.

## Architecture and data model

- Keep the generated bundled catalog and its LaTeX sources immutable. Store captured recipes as user-owned records in SwiftData, separate from `CookbookCatalog` and generated `recipes.json`.
- Add an imported-recipe model with a stable local ID, editable title and recipe content, source URL, capture and edit dates, and any small provenance needed to diagnose extraction. Store ingredient and instruction collections as per-record Codable payloads while keeping fields used for browsing queryable. Preserve the captured text even if the source later changes.
- Introduce a shared recipe presentation boundary so existing recipe detail, cooking, print, grocery, dinner-planning, notes, photos, and usage flows can work with either a bundled recipe or an imported one. Keep IDs distinct so user data attached to one recipe cannot collide with bundled recipe IDs.
- Add the SwiftData model to the existing container. Review the current container's migration behavior and preserve existing notes, photos, cooking progress, dinner plans, and usage records; use a versioned migration only if the additive model requires one.
- Use a Safari Share or Action extension with Safari JavaScript preprocessing to capture the current page's URL and relevant rendered recipe content after the user invokes Cookbook. Pass a bounded, sanitized capture to the main app for LLM processing. Do not use `SFSafariViewController` as the capture surface: Apple documents that its host app cannot inspect webpage interactions or website data, and recommends `WKWebView` only when app-controlled web-content interaction is needed. The user's requested Safari flow instead depends on Safari's extension handoff. See [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller) and [Accessing a Webpage from an App Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html).
- Treat webpage text as untrusted input. Ask the configured LLM provider for a strict recipe structure (title, yield when present, ingredient groups/quantities, and ordered instructions); validate and normalize the response before showing an editable preview. If cloud processing is used, disclose that captured page content is sent to the configured provider and transmit only the relevant bounded content. Never treat instructions found in the page as instructions to the model or app.
- Since the user browses the page in Safari and explicitly invokes capture, the app does not need to impersonate Safari or independently fetch the page with a custom user agent. Some pages may still hide content from extension scripts, require additional Safari website access, or block extraction; report those cases clearly and preserve a manual-entry fallback.

## Basic test cases

- In Safari, open a recipe link, allow Cookbook's Share/Action extension access, and invoke Import: the extension returns the current URL and captured page content to Cookbook without a separate URL fetch.
- Capture a dynamically rendered recipe page: the LLM returns an editable preview with title, quantities, ingredients, and ordered steps; saving creates one imported recipe with its source URL.
- Capture a page with no recipe, incomplete content, blocked extension access, or no network for the LLM: show a specific recoverable error, save no partial record, and allow retry or manual entry.
- Include adversarial text in page content: it is treated as recipe-page data, the response is constrained to the recipe schema, and invalid or incomplete output is rejected or visibly corrected in the preview.
- Edit the LLM result before saving, then relaunch with the source site unavailable: the saved recipe and edits remain available locally.
- Open an imported recipe and use supported existing actions such as cooking, printing, notes, groceries, and dinner planning: each action uses the imported recipe's stable ID and leaves bundled recipes and other records unchanged.
- Open an existing library after adding the SwiftData model: existing notes, photos, sessions, dinner plans, and usage data remain intact.

## High-level implementation details

1. Add an iOS Safari Share/Action extension target to the Xcode project and prototype Safari JavaScript preprocessing that returns the current URL and bounded recipe-relevant page content. Confirm the exact extension handoff supported on the project's iOS 17 deployment target and document Safari website-access/setup steps for users.
2. Add a handoff from the extension into Cookbook, using a narrowly scoped App Group or extension context as required. Keep any temporary page capture short-lived and bounded; remove it after import succeeds or is cancelled.
3. Build an import service that sends the sanitized page capture to the configured LLM provider, requests a strict structured recipe result, validates required fields and sizes, and surfaces provider, network, permission, and malformed-output errors. Reuse the repository's existing LLM configuration and request patterns where suitable; do not silently send page content to a new provider.
4. Add the SwiftData imported-recipe record and additive model-container registration. Present an editable confirmation step before saving a complete durable snapshot with its source URL; define duplicate detection and manual-entry fallback.
5. Extend recipe browsing and the shared recipe actions to include imported records while leaving bundled catalog generation, labels, and source recipes unchanged. Preserve source URL and captured recipe through edits and relaunch.
6. Verify Safari-to-extension handoff, rendered and restricted pages, website permission denial, LLM success/failure/invalid output, prompt-injection fixture, review edits, save/relaunch, duplicate handling, and data-preserving migration. Use relevant Makefile catalog and app build checks; do not deploy automatically.

Material risk: adding and enabling a Safari extension is more involved than a URL paste field, and access depends on Safari invoking the extension and permitting webpage access. Keep manual entry available. Decide whether the LLM request should use only the existing configured cloud provider, also offer supported on-device processing, or provide an explicit choice; in every case explain what page data is processed and where it goes.

Risks and decisions to settle: sites may block direct requests or require authentication, render only after scripts run, or change their markup; extraction quality will vary. Decide whether Safari share-sheet handoff is a later convenience, whether imported recipes need image capture, and which existing actions are in the first implementation scope. Keep manual correction available so a site-specific parser failure does not lose the recipe.
