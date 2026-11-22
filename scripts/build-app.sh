#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
CARTA_INFO="scripts/Info.plist"
for CARTA_NAME_KEY in CFBundleName CFBundleDisplayName; do
  if [ "$(/usr/libexec/PlistBuddy -c "Print :$CARTA_NAME_KEY" "$CARTA_INFO")" != "Carta" ]; then
    printf '%s must be Carta. Set the version in CFBundleShortVersionString.\n' "$CARTA_NAME_KEY" >&2
    exit 1
  fi
done
CARTA_SDK="$(xcrun --sdk macosx --show-sdk-path)"
CARTA_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
CARTA_MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CARTA_INFO")"
# AppKit selects its window appearance using the linked SDK recorded in the executable.
CARTA_BUILD=(-c release --disable-sandbox --cache-path "$PWD/.build/package-cache" --manifest-cache local
  --sdk "$CARTA_SDK" -Xlinker -platform_version -Xlinker macos -Xlinker "$CARTA_MIN_OS" -Xlinker "$CARTA_SDK_VERSION")
swift build "${CARTA_BUILD[@]}" "$@"
CARTA_BIN="$(swift build "${CARTA_BUILD[@]}" "$@" --show-bin-path)"
xcrun vtool -show-build "$CARTA_BIN/Carta" | awk -v sdk="$CARTA_SDK_VERSION" '
  $1 == "sdk" { found++; if ($2 != sdk) mismatch++ }
  END { if (!found || mismatch) { print "SDK macOS inatteso nel binario di Carta" > "/dev/stderr"; exit 1 } }'
CARTA_STAGE="$(mktemp -d "$PWD/.build/release.XXXXXX")"
trap 'rm -rf "$CARTA_STAGE"' EXIT
CARTA_APP="$CARTA_STAGE/Carta.app"
CARTA_OUTPUT="$PWD/dist/Carta.app"
CARTA_ZIP="$PWD/dist/Carta.zip"
mkdir -p "$CARTA_APP/Contents/MacOS" "$CARTA_APP/Contents/Resources"
cp "$CARTA_BIN/Carta" "$CARTA_APP/Contents/MacOS/Carta"
cp -R "$CARTA_BIN/Carta_Carta.bundle" "$CARTA_APP/Contents/Resources/"
cp "$CARTA_INFO" "$CARTA_APP/Contents/Info.plist"
cp Artwork/Carta.icns Artwork/Assets.car "$CARTA_APP/Contents/Resources/"
# Include the project license and upstream notices in the app bundle.
CARTA_LICENSES="$CARTA_APP/Contents/Resources/Licenses"
mkdir -p "$CARTA_LICENSES"
cp LICENSE Sources/Carta/Resources/vendor/*-LICENSE*.txt "$CARTA_LICENSES/"
sed 's|Sources/Carta/Resources/vendor/||g' THIRD_PARTY_NOTICES.md > "$CARTA_LICENSES/THIRD_PARTY_NOTICES.md"
codesign --force --deep --sign - "$CARTA_APP"
mkdir "$CARTA_STAGE/contents"
ditto "$CARTA_APP" "$CARTA_STAGE/contents/Carta.app"
ditto Artwork/Carta.icon "$CARTA_STAGE/contents/Carta.icon"
ditto -c -k --norsrc --noextattr "$CARTA_STAGE/contents" "$CARTA_STAGE/package.zip"

# Publish the complete bundle so removed resources cannot survive a rebuild.
mkdir -p "$PWD/dist"
if [ -e "$CARTA_OUTPUT" ]; then
  mv "$CARTA_OUTPUT" "$CARTA_STAGE/previous.app"
fi
if ! mv "$CARTA_APP" "$CARTA_OUTPUT"; then
  if [ -e "$CARTA_STAGE/previous.app" ]; then
    mv "$CARTA_STAGE/previous.app" "$CARTA_OUTPUT" || trap - EXIT
  fi
  exit 1
fi
mv "$CARTA_STAGE/package.zip" "$CARTA_ZIP"
printf '\nApp pronta: %s\nArchivio: %s\n' "$CARTA_OUTPUT" "$CARTA_ZIP"
