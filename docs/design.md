# Mobile app design

The app uses native SwiftUI navigation with three tabs: Recipes, Dinner, and
Settings. Recipe browsing uses a photo-first grid while sharing search and
category filters. Recipes can open cover generation or image history from the
ellipsis menu; Settings groups the shared OpenAI API-key editor first, followed
by image generation and meal-planning controls. Recipe image settings provide
provider/model controls, missing-cover bulk runs, and persistent batch history.
When a bulk run finishes, a review screen previews its generated covers and
links to the Recipes browser filtered to that run. The Image
Playground sheet is only installed while an on-device generation is being
presented, and starts with a finished-dish concept plus recipe context. A saved
cover takes precedence over the bundled thumbnail.

Recipe pages place title, introduction, ingredients, and method first. The
ellipsis menu exposes groceries, notes, photos, print, and recipe image
management. Cooking mode removes
the surrounding recipe content and emphasizes the current step and ingredients
with large type, step count, and previous/next controls.

Use system typography, semantic colors, native list/form controls, and
accessibility labels. Preserve Dynamic Type behavior and test dark appearance,
VoiceOver order, and small screens during visual acceptance. The repository
does not yet include reviewed simulator screenshots.
