# Capture recipes from Safari

Cookbook captures recipe pages from Safari on iPhone. It does not open the site in an embedded browser or make a second request with an app-specific user agent.

## Use the capture action

1. Open the recipe page in Safari and wait for the page content to finish loading.
2. Tap **Share** and choose **Cookbook**. If Cookbook is not in the action list, scroll to **Edit Actions** and enable it.
3. When iOS asks for webpage access, allow it for the current page. Safari may offer limited or one-time access; the action needs page access to read the rendered recipe text.
4. Cookbook shows a success confirmation and asks you to open the app to review the capture. Tap **Done**, then open Cookbook. iOS returns to Safari; it does not let a Share extension force-open its containing app. Apple documents `NSExtensionContext.open` for Today and iMessage extensions, not Share extensions ([Apple documentation](https://developer.apple.com/documentation/foundation/nsextensioncontext/open%28_%3Acompletionhandler%3A)). The pending capture opens automatically in Cookbook.
5. Review the extracted recipe in the same detail layout used for saved recipes, including its page photo when available. Tap **Save to Recipes** or **Cancel**; fields are not edited during this review.
6. After saving, Cookbook offers **Open recipe**. The Settings page keeps recent Safari captures in their own section, separate from Paprika file imports.

The share extension reads the current URL, page title, Recipe JSON-LD when present, rendered page text, and the best available recipe image URL (structured Recipe image, social preview image, or a large visible image). It bounds the text before handing it to Cookbook. Cookbook sends that capture to the configured OpenAI model for structured extraction; it does not send it to a new provider or fetch the recipe page independently. Each ingredient is stored with separate `amount`, `unit`, and `description` fields. The amount accepts only a numeric quantity (including fractions and ranges); unit and description are kept separately in the Codable model. Legacy `quantity`/`name` payloads are normalized as they decode, and new saves encode only the structured fields. The Markdown representation follows the recipe library convention: **Quantity** is only the amount and **Ingredient** begins with the unit, then the food description. For example, `2 pounds 85 percent lean ground beef` becomes `2 | pounds 85 percent lean ground beef`. A deterministic cleanup pass repairs common LLM field-placement mistakes and splits a clearly marked `plus` or `and` followed by another measurement. The same row formatter is used for Markdown export. During extraction, Cookbook says this typically takes about 10–20 seconds. It tries the supplied photo URL using a normal image request and saves a successfully loaded image with the recipe. If that request fails, the saved recipe still offers **Generate Recipe Cover**. Saved recipes and source URLs are stored locally in the Cookbook library. Run `make recipe-import-test` to check the structured ingredient schema, legacy repair, and every ingredient row in the supplied real chili export.

Local simulator screenshots of the three sample pages and the reported saved-recipe screen are kept under `build/recipe-capture-fixtures/` for reproducing the review/save flow.

## Limits

Safari shares its current page session, cookies, sign-in state, and browser user agent with the site. This avoids failures caused by a separate scraper using a different user agent, but does not guarantee that every page can be captured. Safari website access, site scripts, paywalls, anti-bot checks, and incomplete page loading can limit what the extension sees. Some sites may block the Safari session itself.

If extraction fails or no API key is configured, retry or cancel the import and check the message shown by Cookbook. The source page is never required after saving.
