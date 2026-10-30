# Personal Recipe Repository and iOS App Integration

## Purpose and status

This document records the intended separation between the personal cookbook
repository and the iOS app, and the ways recipes should move between them. It
is a planning document: the feed, app exports, and repository import scripts
described here are proposed work unless an existing implementation is linked
explicitly below.

The current repository architecture is documented in
[Mobile App Architecture](architecture.md). Today, Markdown files in
`recipes/` are the authoritative recipe source, and the mobile catalog is
generated from them. The future separation should preserve that readable
source of truth while allowing the app to hold and exchange recipes on its own.

## Ownership boundaries

### iOS app

The app is the mobile place to browse, capture, import, read, cook from, and
print recipes. Its planned responsibilities are:

- Scrape recipes from web pages, then let the user review and edit the result
  before saving it.
- Import common recipe-manager formats, including individual Paprika recipes
  and multi-recipe Paprika exports.
- Preserve recipe provenance: where a recipe came from and the kind of source
  it came from (for example, a website, Paprika import, manual entry, or the
  personal cookbook repository).
- Keep a local fixture containing the owner's live recipes for offline use and
  development. Decide whether this fixture remains test/sample data or becomes
  a generated app catalog as the repository and app are separated.
- Generate a printable PDF and a hostable HTML representation of app recipes.
  The HTML design can be refined iteratively.

Captured and imported recipes should be app-owned records until the owner
chooses to publish or transfer them to the personal cookbook repository.

### Personal cookbook repository

The repository is the long-term, reviewable home for the owner's canonical
recipes and publishing tools. Its planned responsibilities are:

- Keep Markdown as the editable source of truth, with stable recipe IDs and
  recipe order in the repository's index.
- Preserve and account for legacy PDF and Markdown material during migration
  and import work.
- Publish a recipe feed that the mobile app can subscribe to.
- Provide scripts to inspect and import Paprika recipe files into the
  repository's Markdown source format.

Generated PDFs, HTML, feeds, and app catalogs are outputs of repository source
or app-owned data. They should not become competing canonical copies without
an explicit ownership decision.

## Recipe interchange and subscriptions

There is no single widely adopted interchange format for complete cookbook
collections. PDF and EPUB are useful for reading and distribution but are not
reliable structured import formats. Recipe manager exports such as Paprika's
are useful within compatible tools, but they are app-specific. Individual
recipe formats also vary.

RSS 2.0 and [Atom 1.0](https://www.rfc-editor.org/info/rfc4287/) are
established formats for subscribing to new or changed web content. They do not
define a common recipe data model by themselves. A
feed entry can announce a recipe and link to it, but importing all ingredients,
steps, and metadata consistently requires an additional recipe format or
agreed payload.

[Cooklang Federation](https://github.com/cooklang/federation/blob/main/spec.md)
is a recipe-focused convention built on RSS or Atom. It links feed entries to
full `.cook` recipe files and defines optional Cooklang metadata extensions
and feed discovery guidance. The specification identifies itself as a draft;
it is a promising option to evaluate, not a universal cookbook standard.

For the repository's feed, decide whether the app should consume Cooklang
payloads directly, use another stable recipe representation, or support more
than one. Keep the feed as the update/discovery mechanism and the recipe file
as the full content. Subscribing to a feed should not silently overwrite an
app-edited or locally captured recipe.

## Recipe movement flows

### Personal repository to app

1. The repository publishes or updates a recipe feed.
2. The app subscribes to the feed and discovers new or changed recipe entries.
3. The app fetches the linked recipe payload and preserves source URL,
   repository identity, and attribution.
4. The app previews changes and resolves conflicts before updating an existing
   local copy.

The feed and payload format, update identity rules, deletion behavior, and
conflict policy remain to be decided.

### Add a recipe through Codex Mobile

1. Open a Codex Mobile session in the personal cookbook project.
2. Ask Codex to add or revise a recipe in the repository's Markdown format.
3. Review the source change and generated outputs through the repository's
   normal workflow.
4. The published feed makes the accepted recipe available to the app.

### Capture in the app, then add to the repository

1. Capture or import a recipe in the app and review/edit it before saving.
2. Export that recipe in a form suitable for a repository contribution.
3. Open a Codex session in the personal cookbook project with the export and
   source provenance available.
4. Convert it to the repository's Markdown source format, check for duplicates,
   and review the changes and generated outputs.
5. Publish the accepted repository recipe through the feed.

The export shape and how the app opens or prepares the Codex session remain to
be designed.

### Bulk app-to-repository import

1. Export all selected app recipes.
2. Import the batch into the personal cookbook project using a repository
   script and the established recipe-conversion skill.
3. Match candidate duplicates by stable identity and content, then present
   proposed merges for explicit confirmation. Do not silently merge recipes.
4. Review accepted additions or merges as Markdown source changes and regenerate
   the repository outputs that depend on them.

The bulk export format, duplicate matching rules, and merge-review interface
remain to be specified.

## Format documentation and related work

- Document Paprika's individual `.paprikarecipe` and collection
  `.paprikarecipes` formats, including media, container/compression details,
  fields, and confirmed versus undocumented behavior.
- Document the Cooklang Federation specification and assess whether it fits
  the repository-to-app feed contract.
- Define a portable app export/import representation that retains stable IDs,
  provenance, source links, recipe content, and media where possible.
- Define how local fixtures, the bundled offline catalog, app-owned records,
  and repository-published recipes appear together in the app.

## Open decisions

- Which feed and recipe payload formats the app will support.
- How repository and app recipe identities map across imports and updates.
- How recipe edits, removals, and conflicts propagate between the two systems.
- Whether app-generated PDF and HTML outputs are individual-recipe exports,
  complete collections, or both, and how the hostable HTML is packaged.
- How existing PDF and Markdown materials are classified and migrated.
- How a reviewed recipe export starts or prepares a Codex Mobile session.
- What duplicate detection and merge confirmation look like for bulk imports.
