# AI Dinner Recommendations from a Description

**Plan status: Approved by the user on 2026-11-13; direction updated on 2026-11-17.**

## User requirements

Let someone describe what they want for dinner and get a small set of relevant suggestions from their active Cookbook recipes. The description is the primary signal. It can include ingredients they have or want to use, a dish or cuisine they are craving, time or effort constraints, or context like “it’s cold out.”

- On the Dinner tab, show a **Plan dinner** button for the next unplanned day: today if no dinner is scheduled or saved for today, and tomorrow if today already has a dinner. Label it with the target day and date. Open a dedicated prompt screen from that button; do not put an always-visible text box on the Dinner tab. Include example prompts, such as “I have a loaf of bread. What could I use it for or pair with for dinner?” and “We have a lot of frozen beef. What could we make?”
- Recommend up to five active recipes from the full library, including imported recipes and excluding deleted recipes. Prefer recipes that use the named ingredients or fit the stated request. Do not require the user to provide weather or configure a location.
- Give each suggestion a short, compelling reason grounded in the recipe and the user's description. Call out how a recipe uses or pairs with a named ingredient when relevant. Do not claim a recipe contains an ingredient or property that is not in its catalog data.
- Let the user open a recipe or add it to the target dinner date using the existing dinner planner. Keep normal dinner planning available if recommendations are unavailable.
- After the user adds a suggested recipe to a dinner date, navigate to that recipe's detail page. Returning to Dinner should show the new dinner entry. Starting Plan dinner again should present a fresh, empty prompt.
- Treat weather as optional context. If the user mentions cold, rain, or another condition in the prompt, use that as part of the request. Do not fetch weather or request location for the default flow. A separately chosen live-weather context can be considered later, but is outside the core plan.

## Architecture and data model

The app already has a `DinnerPlannerView` in `ios/Cookbook/SettingsAndDinner.swift`, recipe assembly there (bundled plus active imported recipes, excluding deleted bundled recipes), and recipe metadata in `ios/Cookbook/Catalog.swift`. The app has manual and AI-assisted dinner planning. Recommendations should feed its existing planner rather than create a parallel dinner data model.

Make recommendations LLM-powered. Provide a freeform user description plus compact structured data for active cookbook recipes (IDs, titles, ingredient lists, labels, introductions/descriptions, pairings, servings, and source type). Ask the model to choose up to five relevant recipes and explain each choice in a short, useful, grounded reason. Require structured output containing only supplied recipe IDs; validate IDs, uniqueness, result count, and reason length before showing results. Instruct the model to prioritize explicit ingredient-use requests and stated constraints, use only supplied recipe facts, avoid inventing recipe ingredients, preparation times, nutrition or dietary claims, and avoid treating a suggested pairing as part of the recipe itself.

Use the existing iOS 26 Foundation Models support for on-device recommendations when available, and the existing OpenAI Responses API client, Keychain key storage, model setting, and provider picker (`aiProvider`, `openAIModel`, `KeychainKey`, `AIDinnerPlanner`, `OnDeviceDinnerPlanner`) for the configured cloud option. Add a dedicated recommendation prompt/schema and provider adapter; reuse current configuration and credential plumbing rather than adding another key. Preserve the existing explicit provider choice: do not silently send the prompt or personal recipe text to the cloud. If cloud processing is selected or enabled, make that clear before the request. No location or weather service is needed for the core flow.

Use the user's description as the main ranking signal, with recipe metadata as grounding. The model may suggest how a recipe could use or pair with an item named by the user, but it must distinguish an explicit recipe ingredient from a separate serving/pairing idea. Do not invent recipes outside the active cookbook in this first version; when there is no good match, say so and let the user refine the prompt or use normal dinner planning.

## Basic test cases

- The recommendation flow accepts a freeform description and does not ask for location or fetch weather.
- The Dinner tab offers Plan dinner for today when today has no dinner, and for tomorrow when today already has one; the prompt appears only after opening that action.
- A prompt naming a loaf of bread ranks applicable active recipes and explains whether the bread is used in the recipe or offered as a separate pairing.
- A prompt about frozen beef favors relevant recipes, accounts for stated constraints, and does not claim unlisted ingredients.
- A prompt that includes weather context, such as “it’s cold out,” can use that as a preference without fetching a forecast.
- On-device generation produces up to five unique active recipe IDs with grounded explanations; malformed, unknown, duplicate, or unsupported recipe IDs are rejected.
- Cloud processing uses existing OpenAI configuration only when the user's provider/settings permit it and clearly communicates when prompt and recipe data will be sent.
- Results include active imported recipes and exclude deleted recipes.
- If Foundation Models is unavailable, cloud processing is disabled, the API key is missing, the network fails, or model output is invalid, show a clear retry/setup state without preventing normal dinner planning.
- A recipe opens from a result and can be added to the date targeted by Plan dinner through the existing dinner-planning flow.
- Saving a suggestion to dinner takes the user to its recipe detail page; going back shows the new dinner record, and reopening Plan dinner starts with an empty prompt.
- An empty or overly broad prompt asks the user to add detail or returns a helpful empty state rather than unsupported claims.

## High-level implementation details

1. Add a Plan dinner action to the Dinner tab for today when it is open or tomorrow when today already has a dinner. Put the freeform prompt, example prompts, and AI request in a dedicated screen with local-only prompt state, and preselect the targeted day when adding a suggested recipe.
2. Add a dedicated structured LLM recommendation request that takes the user description and active cookbook recipe data, prioritizes the described ingredients and constraints, and validates the returned recipe IDs and explanations.
3. Prefer Foundation Models on supported devices; route to the existing OpenAI Responses API configuration when the user's provider choice permits. Keep cloud data use explicit and do not silently fall back from on-device to cloud.
4. Add loading, recommendation, empty, retry, provider/setup, and unavailable states. Keep normal dinner planning accessible.
5. Reuse existing recipe navigation and dinner scheduling. After adding a suggestion, replace the prompt route with the selected recipe detail route so returning to Dinner shows the new dinner and a future Plan dinner visit starts fresh. Do not add WeatherKit, weather web search, saved weather locations, or location permissions to this feature's core flow. Weather mentioned by the user is ordinary prompt context.
6. Add focused tests for prompt input construction, structured model output validation, active/imported/deleted recipe handling, recipe-grounded ingredient explanations, provider/privacy behavior, and service failure states.
7. After implementation, run `make catalog-check`, then `make sim-build` and `make phone-deploy` as required by the repository workflow. Keep simulator and phone builds sequential, and report any build or device blocker with the verification that remains incomplete.
