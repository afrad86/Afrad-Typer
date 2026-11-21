#!/bin/bash
# Builds "Afrad Typer.app" (universal: Apple Silicon + Intel) and "Afrad Typer.zip"
set -euo pipefail
cd "$(dirname "$0")"
EXE="TypingPractice"
BUNDLE="Afrad Typer"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift was not found. Install Xcode or the Command Line Tools first."
  exit 1
fi

OUT=".build-manual"
rm -rf "$OUT"
mkdir -p "$OUT"

ARCHES=()
for a in arm64 x86_64; do
  echo "Compiling for $a ..."
  if swiftc -parse-as-library -O -target "$a-apple-macos12.0" Sources/TypingPractice/*.swift -o "$OUT/$EXE-$a"; then
    ARCHES+=("$a")
  else
    echo "  (could not build for $a)"
  fi
done

if [ "${#ARCHES[@]}" -eq 0 ]; then
  echo ""
  echo "Build failed. Copy the error messages above."
  exit 1
fi

if [ "${#ARCHES[@]}" -eq 2 ]; then
  lipo -create -output "$OUT/$EXE" "$OUT/$EXE-arm64" "$OUT/$EXE-x86_64"
else
  echo "Note: built for ${ARCHES[0]} only."
  cp "$OUT/$EXE-${ARCHES[0]}" "$OUT/$EXE"
fi

# App icon: turn Resources/AppIcon.png into an .icns file
if [ -f Resources/AppIcon.png ]; then
  ICONSET="$OUT/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "$s" "$s" Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$d" "$d" Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns" || echo "  (icon conversion failed - continuing without it)"
fi

# Remove older builds
rm -rf "$BUNDLE.app" "TypingPractice.app" "$BUNDLE.zip" "TypingPractice.zip"

mkdir -p "$BUNDLE.app/Contents/MacOS" "$BUNDLE.app/Contents/Resources"
cp "$OUT/$EXE" "$BUNDLE.app/Contents/MacOS/$EXE"
cp Resources/Info.plist "$BUNDLE.app/Contents/Info.plist"
VERSION="$(tr -d '[:space:]' < VERSION)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUNDLE.app/Contents/Info.plist"
if [ -f Resources/Logo.png ]; then
  cp Resources/Logo.png "$BUNDLE.app/Contents/Resources/Logo.png"
fi
if [ -f Resources/books.json ]; then
  cp Resources/books.json "$BUNDLE.app/Contents/Resources/books.json"
fi
if [ -f Resources/Pacifico-Regular.ttf ]; then
  cp Resources/Pacifico-Regular.ttf "$BUNDLE.app/Contents/Resources/"
  cp Resources/Pacifico-OFL.txt "$BUNDLE.app/Contents/Resources/" 2>/dev/null || true
fi
if [ -f "$OUT/AppIcon.icns" ]; then
  cp "$OUT/AppIcon.icns" "$BUNDLE.app/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature so macOS will run it locally
codesign --force --deep --sign - "$BUNDLE.app"

ditto -c -k --keepParent "$BUNDLE.app" "$BUNDLE.zip"

# Copy for the GitHub release (not stored in the repository itself)
mkdir -p release
cp "$BUNDLE.zip" release/Afrad-Typer.zip
# Update information (big files come from the GitHub release of this version)
python3 tools/make_release_info.py
rm -rf "$OUT"

echo ""
echo "Done:"
echo "  $BUNDLE.app  (drag into Applications)"
echo "  $BUNDLE.zip  (copy this to your office Mac)"
open -R "$BUNDLE.app" || true
