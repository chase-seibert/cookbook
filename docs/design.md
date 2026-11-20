# Mobile app design

The app uses native SwiftUI navigation with three tabs: Recipes, Dinner, and
Settings. Recipe browsing uses a photo-first grid while sharing search and
category filters. Recipe image generation and image history are available from
the recipe image controls; Settings groups the shared OpenAI API-key editor first,
followed by image generation and meal-planning controls. Recipe image settings provide
provider/model controls, missing-cover bulk runs, and persistent batch history.
When a bulk run finishes, a review screen previews its generated covers and
links to the Recipes browser filtered to that run. The Image
Playground sheet is only installed while an on-device generation is being
presented, and starts with a finished-dish concept plus recipe context. A saved
cover takes precedence over the bundled thumbnail.

Recipe pages place the artwork first, followed by the title and recipe content.
The toolbar has Start Cooking, Plan, and Share actions in that order. Plan groups
groceries and dinner planning; Share groups printing and recipe exports. Tapping
artwork reveals an Edit Image popover that dismisses when tapped away; recipes
without artwork show Add Image in its place. The photo picker opens directly and
reports save errors. The metadata order near the bottom is My Notes, dinner usage,
source labels, then the tappable category. The category uses the app's green
accent so it reads as an active control. Delete Recipe asks for confirmation and
moves the recipe to Deleted Recipes; its deleted detail has a matching Restore
Recipe button at the bottom. Settings → Library links to Deleted Recipes. Cooking
mode removes the surrounding recipe content and emphasizes the current step and
ingredients with large type, step count, and previous/next controls.

Use system typography, semantic colors, native list/form controls, and
accessibility labels. Preserve Dynamic Type behavior and test dark appearance,
VoiceOver order, and small screens during visual acceptance. The repository
does not yet include reviewed simulator screenshots.
