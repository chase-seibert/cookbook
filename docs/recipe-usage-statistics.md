# Recipe usage statistics

Cookbook stores recipe usage in its local SwiftData store, keyed by the stable recipe ID in the bundled catalog. The app records a recipe open when a full recipe detail screen appears, including bundled and imported recipes opened from the main list or import history. Preview-only import review screens do not count as recipe opens. Each open increments `recipeOpenCount` and updates optional `lastOpenedAt`. It records one grocery add flow only after EventKit accepts all selected, nonduplicate ingredients and commits the batch successfully. Ingredient count does not affect the grocery-flow count. Cancelled, duplicate-only, partially saved, and failed flows are not counted. Grocery activity updates `updatedAt`, but never changes `lastOpenedAt`.

The Settings screen shows every current catalog recipe, including recipes with zero counts, and can export a CSV with recipe ID, current title, open count, completed grocery-flow count, and last update time. Records for IDs no longer in the catalog remain visible as unknown recipes and are included in the export. The Paprika collection export selector uses `lastOpenedAt` for Most recent ordering; never-opened recipes follow opened recipes, and ties use case-insensitive title order.

These counts describe use on this installation only. The app has no analytics backend, and counts do not aggregate across people or devices. Treat them as a local signal rather than broad popularity data.

## Storage compatibility

`RecipeUsageStats` is an additive entity in the existing SwiftData model container. The optional `lastOpenedAt` field is an additive model change; existing rows without an open timestamp remain valid and sort after rows with a timestamp. The app uses SwiftData's default lightweight migration for additive model changes; existing notes, photos, cooking progress, and dinner records retain their existing entity definitions. Any future incompatible change to a stored entity should introduce an explicit versioned schema and migration plan.
