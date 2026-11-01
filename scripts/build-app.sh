#!/usr/bin/env bash
# Builds Klieg.app (with the klieg CLI inside) into ./build, using only the Command Line Tools.
#   bash scripts/build-app.sh            build only
#   bash scripts/build-app.sh --install  also install it in /Applications and link the klieg command
set -euo pipefail
cd "$(dirname "$0")/.."

# Never the Xcode app: point the toolchain at the Command Line Tools even if xcode-select picks Xcode.
export DEVELOPER_DIR="${KLIEG_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

CONFIG=release
APP="build/Klieg.app"
VERSION=$(sed -n 's/.*string = "\(.*\)".*/\1/p' Sources/KliegKit/Version.swift)
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")

echo "→ Building ($CONFIG) with $DEVELOPER_DIR"
swift build -c "$CONFIG" --product klieg
swift build -c "$CONFIG" --product KliegApp
BIN=$(swift build -c "$CONFIG" --show-bin-path)

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/KliegApp" "$APP/Contents/MacOS/KliegApp"
cp "$BIN/klieg" "$APP/Contents/Helpers/klieg"

if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "→ Drawing icon"
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Klieg</string>
  <key>CFBundleDisplayName</key><string>Klieg</string>
  <key>CFBundleIdentifier</key><string>dev.ry-ops.klieg</string>
  <key>CFBundleExecutable</key><string>KliegApp</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>KliegCommit</key><string>${COMMIT}</string>
</dict>
</plist>
PLIST

echo "→ Signing (ad hoc)"
codesign --force --sign - "$APP/Contents/Helpers/klieg"
codesign --force --sign - "$APP"
echo "✓ Built $APP ($VERSION)"

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications"; [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST" "$HOME/.local/bin"
  osascript -e 'tell application "Klieg" to quit' >/dev/null 2>&1 || true
  rm -rf "$DEST/Klieg.app"; cp -R "$APP" "$DEST/"
  ln -sf "$DEST/Klieg.app/Contents/Helpers/klieg" "$HOME/.local/bin/klieg"
  echo "✓ Installed to $DEST/Klieg.app, and linked ~/.local/bin/klieg"
fi
