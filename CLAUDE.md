# Keysy

macOS menu bar app (Swift Package, no Xcode project). Build with `./build.sh`.

## Releases

Follow [RELEASING.md](RELEASING.md). Always release with `./release.sh X.Y.Z` — it signs with
Developer ID, notarizes (keychain profile `keysy-notary`), verifies Gatekeeper, tags `vX.Y.Z`, and
publishes `Keysy.dmg` + `Keysy.zip` (the zip is what the in-app updater installs).
Never ship an un-notarized build: users get a "Move to Trash"-only dialog.
