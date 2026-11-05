# Preserve ingredient and instruction order in the iOS app

## User requirements

- As a user, I want the iOS recipe view to show ingredient groups and instructions in the same order they appear in my Markdown source, so that recipes that alternate between preparation phases remain easy to follow.
- As a user, I want ingredient groups and instruction wording to remain intact, so that preserving order does not lose quantities, group boundaries, or cooking steps.
- As a user, I want future recipes imported through the LLM parser to preserve ingredient-group and instruction order when the source makes that order clear, so that imported recipes follow the same preparation flow as my Markdown recipes.
- As a user, I want my existing saved imports left untouched and still readable, so that this change does not rewrite the few recipes already on my phone.
- Scope assumption: this plan covers the bundled Markdown catalog, future LLM-parsed web and magazine imports, the recipe detail presentation, and the app’s own print preview/PDF. Existing saved imports are not backfilled. Non-LLM import formats and step-by-step cooking mode keep their current interaction unless implementation review finds they must consume ordered content too.

## Architecture and data model

The Markdown parser already produces ordered recipe blocks, but `generate_mobile_catalog.py` currently splits ingredient tables and instruction paragraphs into separate arrays. `Recipe` likewise exposes `ingredients` and `steps` separately, and the detail and print views render those arrays in separate sections. `RecipeIngredient.group` can label an ingredient, but it cannot say where its group occurs relative to a step. This pattern is common in the actual source: a parser scan found 63 of 68 recipe files with multiple ingredient tables and at least one later table after an instruction.

Add a normalized ordered-reference model while retaining the flat arrays existing consumers use:

```text
Recipe
  ingredients: [RecipeIngredient]              // flat lookup for groceries/imports
  ingredientGroups: [RecipeIngredientGroup]?   // grouping and membership
  steps: [RecipeStep]                          // flat lookup for cooking/resume
  contentOrder: [RecipeContentReference]?      // canonical order when present

RecipeIngredientGroup
  id: String
  title: String?                               // optional; Markdown tables can be untitled
  ingredientIDs: [String]

RecipeContentReference
  kind: "ingredientGroup" | "step"
  id: String                                   // group ID or step ID
```

Each group references its ingredient rows, and `contentOrder` interleaves group IDs and step IDs. Keep `RecipeIngredient.group` as a legacy/display-label compatibility field for old web and magazine imports; it is not the order model. Validate that references resolve, each step appears once, groups do not duplicate ingredient membership, and every ingredient is represented. The detail view walks `contentOrder`, looks up the referenced group or step, and renders the group's rows together at that position. Keep step numbering based on step order, not the absolute block index. For existing recipes with no group title, keep the group boundary visually clear with spacing or a divider.

Examples from the source show why both grouping and cross-type order matter:

- `recipes/deepdish.md`: dough group → six dough steps → sauce group → sauce step → cheese/sausage group → assembly step → bake/rest step.
- `recipes/cashew_chicken.md`: first marinade group → two steps → oil group → two steps → cashew group → step → chile/garlic group → step → onion group → two steps → sauce group → two steps → scallion group → final step.
- `recipes/pizza.md`: starter group → starter step → remaining dough group → three dough steps → sauce group → sauce and shaping steps → mozzarella/pepperoni group → topping and baking steps.

For Deep Dish Pizza, the persisted recipe can keep the current flat ingredient and step records, add these group records, and sequence only stable references:

```json
{
  "ingredientGroups": [
    { "id": "deepdish-group-1", "title": null, "ingredientIDs": ["deepdish-ingredient-1", "deepdish-ingredient-2", "deepdish-ingredient-3", "deepdish-ingredient-4", "deepdish-ingredient-5", "deepdish-ingredient-6", "deepdish-ingredient-7"] },
    { "id": "deepdish-group-2", "title": null, "ingredientIDs": ["deepdish-ingredient-8", "deepdish-ingredient-9", "deepdish-ingredient-10", "deepdish-ingredient-11", "deepdish-ingredient-12", "deepdish-ingredient-13", "deepdish-ingredient-14"] },
    { "id": "deepdish-group-3", "title": null, "ingredientIDs": ["deepdish-ingredient-15", "deepdish-ingredient-16"] }
  ],
  "contentOrder": [
    { "kind": "ingredientGroup", "id": "deepdish-group-1" },
    { "kind": "step", "id": "deepdish-step-1" }, { "kind": "step", "id": "deepdish-step-2" },
    { "kind": "step", "id": "deepdish-step-3" }, { "kind": "step", "id": "deepdish-step-4" },
    { "kind": "step", "id": "deepdish-step-5" }, { "kind": "step", "id": "deepdish-step-6" },
    { "kind": "ingredientGroup", "id": "deepdish-group-2" },
    { "kind": "step", "id": "deepdish-step-7" },
    { "kind": "ingredientGroup", "id": "deepdish-group-3" },
    { "kind": "step", "id": "deepdish-step-8" }, { "kind": "step", "id": "deepdish-step-9" }
  ]
}
```

The renderer resolves each group reference to its ingredient rows and each step reference to its existing step record. The source tables are untitled, hence `title: null`; the group IDs preserve their distinct boundaries without inventing headings.

The current web and magazine LLM parsers return separate ingredient and instruction arrays; ingredient records may have a group label, but the response cannot interleave groups and instructions. Change both structured response schemas and prompts to return an ordered list of blocks. Ingredient-group blocks contain an optional title and structured ingredient rows; instruction blocks contain one instruction. Ask the LLM to preserve order only when it is recoverable from the page or photo, retain source wording, and avoid inventing missing ingredients or instructions. Map the sequence into `ingredientGroups`, flat `ingredients`, `steps`, and `contentOrder` before preview and save. If source order cannot be established, use a documented safe fallback of all ingredient groups followed by all steps.

Rebuild the bundled catalog from all 68 Markdown files so exact table/step order and group membership come from source. Do not run a launch-time or bulk backfill on existing Paprika, web, or magazine records. Their `Recipe` payloads must remain decodable when the new optional group/order fields are absent. For display only, synthesize a legacy order in memory: use existing ingredient group labels where present (otherwise one untitled group), followed by the existing steps. This compatibility view must not rewrite stored `recipeData`; new LLM-parsed imports save the ordered fields from creation. This is a Codable payload extension, not a SwiftData entity or column migration.

## Basic test cases

- Generate Deep Dish Pizza and verify its ordered content is dough ingredients, the dough instructions in source order, sauce ingredients, sauce instruction, topping ingredients, then the remaining instructions and notes where supported.
- Verify the model distinguishes repeated groups even when their source tables have no titles, and that `contentOrder` can reference a group, several steps, then another group without flattening or sorting them.
- Parse/import a recipe through the LLM flow with multiple ingredient groups between instructions; verify the structured response retains that sequence through preview, save, reload, and detail presentation.
- Import a web recipe and a magazine recipe whose sources clearly interleave groups and instructions; verify the parser preserves that order. When source order is ambiguous, verify it uses the documented groups-then-steps fallback rather than guessing.
- Verify each source ingredient table stays a separate group, each instruction appears exactly once, and all quantities, step IDs, and ingredient references remain valid.
- Open an interleaved recipe and confirm the detail view displays the generated group/step sequence; confirm print preview/PDF follows the same order.
- Decode a legacy catalog entry and legacy saved imports without ordered-content data; verify they remain readable using an in-memory legacy order and that listing/opening them does not rewrite their stored payloads.
- Check a recipe with one initial ingredient table and subsequent steps; verify its familiar sequence remains correct and no empty groups or duplicated content appear.
- Verify cooking mode can still navigate and resume by step ID, and grocery collection still includes each ingredient once.

## High-level implementation details

1. Extend the mobile catalog generator to emit a `RecipeIngredientGroup` for each ingredient table and `contentOrder` references for each table and instruction paragraph, directly from the parser’s existing block sequence. Retain current flat arrays, ingredient IDs, step IDs, and metadata behavior.
2. Add Codable group/reference types and a backward-compatible decode/view path for entries that predate them. Validate group membership, reference uniqueness, and missing references; if order metadata is absent, synthesize groups from existing ingredient labels (or one untitled group) followed by steps in memory only.
3. Extend the web and magazine LLM parser schemas/prompts to return ordered ingredient-group and instruction blocks. Preserve sequence through review, edits, save, and reload; use the documented fallback when the source cannot establish order.
4. Update the recipe detail view to render ingredient groups and steps from the ordered entries, retaining the current quantity styling, step numbering, section headings, and note placement. Update the in-app print preview and PDF renderer to use the same order. Leave cooking-mode progression and grocery aggregation based on their existing step/ingredient collections.
5. Add generator, model, and LLM response mapping tests for interleaving, group identity, reference integrity, new-import round trips, ambiguity fallback, and legacy decoding without payload writes. Regenerate the catalog with `make catalog`, then run `make catalog-check` and the relevant test targets.
6. Build the app with `make sim-build` and complete the repository-required `make phone-deploy` workflow for the iOS code changes.

Key risks are losing table boundaries while flattening data, the LLM returning a plausible but unsupported order, changing step or ingredient identities used by notes and cooking-session resume records, and breaking old Codable recipe payloads. Keep existing IDs stable, validate ordered references before save, and test ambiguous-source fallback. Existing saved imports cannot recover exact source order when that order was never stored, so leave their data untouched and use only an in-memory legacy presentation order. Confirm during implementation whether notes and any other in-app recipe rendering surfaces also need source-position preservation; external formats with fixed separate lists cannot express interleaving without a separate export design.
