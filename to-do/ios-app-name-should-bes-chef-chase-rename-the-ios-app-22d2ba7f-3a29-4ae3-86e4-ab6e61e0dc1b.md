## User requirements

- As a user, I want the iOS app to be named “Chef Chase,” so that I can recognize it by its intended name on my device and in iOS surfaces that identify the app.
- As a user, I want the app icon to show a simple cartoon portrait of me wearing a chef's hat, using the app's olive-and-cream palette, so that Chef Chase has a recognizable personal cooking identity.
- Keep the work focused on the iOS app’s user-visible name and icon. Assume internal project, target, scheme, and bundle identifiers remain stable; no broader product rename or App Store name-availability work is requested. Treat Chase as a person’s name; the icon does not need a literal chase motif.

## Architecture and data model

No material architecture, persistence, schema, or data-model change is required. Set the main app’s display name explicitly rather than relying on the Xcode product name, and replace the existing app icon in its asset catalog. Keep `com.cseibert.Cookbook` and the Share Extension bundle identifier unchanged so existing installs, app data, entitlements, and extension relationships retain their identity. Align the Share Extension’s displayed name with the app where iOS presents it; internal `Cookbook` type names and storage paths can remain as implementation identifiers.

## Basic test cases

- Install or update the app on a simulator and confirm its Home Screen label is “Chef Chase.”
- Confirm the selected square cartoon portrait icon appears on the Home Screen and remains recognizable when viewed at small sizes such as 40–60 px. Keep the hat and face within the icon safe area, avoid text, and leave rounded-corner masking to iOS.
- Confirm the app still launches and can read its existing local recipe library after updating an installation with the same bundle identifier.
- Open a supported share flow and confirm iOS identifies the extension as “Chef Chase” and that the handoff still reaches the app.
- Inspect the built app and extension bundle identifiers to confirm they remain unchanged.

## High-level implementation details

1. Add `CFBundleDisplayName` with value `Chef Chase` to `ios/Cookbook/Info.plist`; this plist currently has no explicit display name and falls back to the product name `Cookbook`.
2. Change the Share Extension’s `CFBundleDisplayName` in `ios/Cookbook/ShareExtension/Info.plist` to `Chef Chase` so the related system surface uses the same name. Leave extension target/product identity and app-facing feature text outside this focused rename unless implementation review finds a concrete inconsistency.
3. Replace `ios/Cookbook/Assets.xcassets/AppIcon.appiconset/AppIcon.png` with the user-selected square cartoon portrait variation, featuring a clean chef hat, simple strokes, and the app's olive-and-cream palette. Keep the face and hat inside the icon safe area, avoid text or pre-rounded corners, and review it at 40–60 px.
4. Verify generated bundle metadata and run the repository’s `make sim-build` and phone-target build workflow after these app-affecting edits. The Makefile’s build targets also run `catalog-check`; no catalog regeneration is needed. Phone installation and launch can be retried once the configured device is unlocked.
5. Main risk is changing an identifier by mistake while renaming. Keep the app and extension bundle IDs, signing team, scheme, target, and persisted data locations stable; confirm the app updates in place rather than appearing as a second installation.
