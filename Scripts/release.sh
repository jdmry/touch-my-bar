#!/bin/bash
#
# Builds a release .app, packages it as a DMG, and updates the Homebrew
# cask to match.
#
# Usage: Scripts/release.sh 0.2.0 [path-to-tap]
#
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [tap-path]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP="${2:-$ROOT/../homebrew-tap}"
DIST="$ROOT/dist"
APP="Touch My Bar.app"
DMG="$DIST/TouchMyBar-$VERSION.dmg"

# The bundle's version is the source of truth; make-app.sh writes the
# Info.plist, so the version has to reach it from here.
export TMB_VERSION="$VERSION"
"$ROOT/Scripts/make-app.sh" release

rm -rf "$DIST"
mkdir -p "$DIST/stage"
cp -R "$ROOT/build/$APP" "$DIST/stage/"
# The drag-to-install target people expect inside a DMG.
ln -s /Applications "$DIST/stage/Applications"

hdiutil create -quiet -volname "Touch My Bar" -srcfolder "$DIST/stage" \
    -ov -format UDZO "$DMG"
rm -rf "$DIST/stage"

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

echo
echo "Built $DMG"
echo "  version: $VERSION"
echo "  sha256:  $SHA"

CASK="$TAP/Casks/touch-my-bar.rb"
if [[ -f "$CASK" ]]; then
    # Only the two lines that change per release.
    /usr/bin/sed -i '' \
        -e "s|^  version \".*\"|  version \"$VERSION\"|" \
        -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" \
        "$CASK"
    echo
    echo "Updated $CASK — commit and push the tap, then:"
else
    echo
    echo "No cask at $CASK; paste this in by hand:"
    echo "  version \"$VERSION\""
    echo "  sha256 \"$SHA\""
    echo
fi

cat <<EOF
  git -C "$ROOT" tag v$VERSION && git -C "$ROOT" push --tags
  gh release create v$VERSION "$DMG" --repo jdmry/touch-my-bar \\
      --title "v$VERSION" --notes "..."
EOF
