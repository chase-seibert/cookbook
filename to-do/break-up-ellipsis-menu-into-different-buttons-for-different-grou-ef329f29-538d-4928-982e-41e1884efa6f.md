## User requirements

- The recipe toolbar has three actions, in this order: Start Cooking (play), Plan (calendar plus), and Share (share icon). Remove the Edit menu.
- Keep Add to Groceries and Add to Dinner in Plan.
- Move Add Note to a plus button beside My Notes. Existing notes remain tappable to edit.
- Move Add Photo, Take Photo, and Generate/Manage Recipe Images to the recipe artwork: tapping existing artwork reveals an Edit Image button; when no image exists, show an Add Image button in its place.
- Put recipe metadata near the bottom in this order: My Notes, dinner usage count, source labels, then category. Keep the active category tappable and give it a clearly enabled foreground color.
- Put Delete Recipe in a red button at the bottom of the recipe content and require confirmation before moving the recipe to Deleted Recipes.
- Put a matching Restore Recipe button at the bottom of deleted recipe details. Make Deleted Recipes easy to find under Settings → Library.
- Keep printing and Markdown, HTML, and Paprika exports in Share.

## Architecture and behavior

The change is centered on `RecipeDetailView` in `ios/Cookbook/CookbookApp.swift`. Reuse existing handlers, sheets, export error states, and conditions. Camera remains disabled when unavailable. Category editing, image management, and deletion remain unavailable for deleted recipes; category editing stays unavailable with no categories. Present the photo picker directly from its view modifier so Add Photo opens it and report save failures visibly. Use an outside-dismissible image popover. Preserve restore behavior. Do not introduce a persistence or schema change.

Update `docs/design.md` to describe the three toolbar buttons and the relocated actions.

## Validation

- Verify the toolbar order and accessible names: Start Cooking, Plan, Share.
- Verify Plan actions and Share print/export flows.
- Verify metadata order is notes, dinner usage, source labels, category; the category appears enabled and can be changed when allowed.
- Verify notes can be added with the My Notes plus button and existing notes still open for editing.
- Verify tapping artwork reveals an Edit Image popover that dismisses when tapped away; with no artwork, Add Image occupies the image area. Verify Add Photo opens the picker, image save failures show an error, and camera availability and image management conditions remain correct.
- Verify Delete Recipe is red and appears after all recipe content, asks for confirmation, and moves the recipe to Deleted Recipes; deleted details show Restore Recipe at the bottom and Settings → Library opens the deleted list.
- Check compact width and Dynamic Type in Simulator.
- Run `make sim-build`, then `make phone-deploy`; report any device launch blocker.
