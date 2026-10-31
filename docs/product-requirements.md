# Product requirements

- As a home cook, I want to browse recipes in a searchable list or photo grid so
  that I can quickly choose what to make. The list follows cookbook chapter and
  source-file order, with collection headings for groups such as Cocktails.
- As a home cook, I want recipe ingredients and instructions in a clean reading
  view so that I can cook without navigating a web page.
- As a home cook, I want to review ingredients and avoid duplicate Reminders
  before adding groceries so that my list stays useful.
- As a home cook, I want one current step and its ingredients in cooking mode so
  that I can focus while preparing food. I can start it from the recipe toolbar
  or the visible Start Cooking button, then advance with Next and Previous.
- As a recipe owner, I want timestamped notes and attached photos to survive app
  updates so that personal recipe history stays with me.
- As a home cook, I want a printable recipe and a saved multi-recipe dinner plan
  so that I can prepare a meal on paper or across several sessions.
- As a home cook, I want to add recipes to a chosen dinner date from the recipe
  menu, then generate a plan from that date and reopen saved plans separately.
- As a home cook, I want an explicitly selected AI provider to help schedule
  several recipes backward from dinner time so that equipment and timing
  constraints are visible.
- As a home cook, I want to generate or regenerate a recipe cover from its page
  and generate missing covers in a resumable Settings run, using either an
  on-device system experience or OpenAI with my Keychain API key. The recipe
  action lives in the ellipsis menu, and the shared OpenAI key settings are
  first in Settings, ahead of image generation and meal planning. Completed
  batch runs preview generated covers before linking to the Recipes browser
  filtered to those results.
- As a home cook, I want earlier saved covers retained and available to restore,
  and each batch run to support filtered review and safe undo of covers that
  have not changed since the run.
- Generated covers remain local, work offline after saving, and are included in
  Paprika exports through the same effective-cover path as other saved photos.
