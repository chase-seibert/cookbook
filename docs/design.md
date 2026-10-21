# Mobile app design

The app uses native SwiftUI navigation with three tabs: Recipes, Dinner, and
Settings. Recipe browsing can switch between a compact title-first list and a
photo-first grid while sharing search and category filters. Recipes without an
image use a quiet neutral placeholder.

Recipe pages place title, introduction, ingredients, and method first. The
ellipsis menu exposes groceries, notes, photos, and print. Cooking mode removes
the surrounding recipe content and emphasizes the current step and ingredients
with large type, step count, and previous/next controls.

Use system typography, semantic colors, native list/form controls, and
accessibility labels. Preserve Dynamic Type behavior and test dark appearance,
VoiceOver order, and small screens during visual acceptance. The repository
does not yet include reviewed simulator screenshots.
