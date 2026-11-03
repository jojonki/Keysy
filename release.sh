#!/bin/bash
# Release Keysy: build, sign (Developer ID), notarize, verify, tag, and publish to GitHub Releases.
# Usage: ./release.sh 0.2.0 [release-notes-file]
# See RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
NOTES_FILE="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-keysy-notary}"
TAG="v$VERSION"

die() { echo "error: $*" >&2; exit 1; }

# --- Pre-flight checks ---
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: ./release.sh X.Y.Z [notes.md]"
[ -z "$NOTES_FILE" ] || [ -f "$NOTES_FILE" ] || die "notes file not found: $NOTES_FILE"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "not on main"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main differs from origin/main (push or pull first)"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
LATEST=$(gh release view --json tagName -q .tagName 2>/dev/null | sed 's/^v//' || true)
if [ -n "$LATEST" ]; then
  [ "$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] && [ "$LATEST" != "$VERSION" ] \
    || die "$VERSION is not newer than the latest release ($LATEST)"
fi
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notary profile '$NOTARY_PROFILE' missing (see RELEASING.md: one-time setup)"

# --- Build + sign + notarize + staple ---
VERSION="$VERSION" NOTARY_PROFILE="$NOTARY_PROFILE" ./build.sh

# --- Verify ---
APP_VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Keysy.app/Contents/Info.plist)
[ "$APP_VER" = "$VERSION" ] || die "built app version $APP_VER != $VERSION"
spctl -a -t exec build/Keysy.app >/dev/null 2>&1 || die "Gatekeeper rejected Keysy.app"
spctl -a -t open --context context:primary-signature build/Keysy.dmg >/dev/null 2>&1 || die "Gatekeeper rejected Keysy.dmg"
xcrun stapler validate build/Keysy.dmg >/dev/null || die "Keysy.dmg not stapled"
TMP=$(mktemp -d); ditto -xk build/Keysy.zip "$TMP"
xcrun stapler validate "$TMP/Keysy.app" >/dev/null || die "app inside Keysy.zip not stapled"
rm -rf "$TMP"
echo "Verified: notarized, stapled, version $VERSION"

# --- Tag + publish ---
git tag "$TAG"
git push -q origin "$TAG"
if [ -n "$NOTES_FILE" ]; then
  gh release create "$TAG" build/Keysy.dmg build/Keysy.zip --title "Keysy $VERSION" --notes-file "$NOTES_FILE"
else
  gh release create "$TAG" build/Keysy.dmg build/Keysy.zip --title "Keysy $VERSION" --generate-notes
fi
echo "Released $TAG"
