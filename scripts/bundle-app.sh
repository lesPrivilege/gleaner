#!/bin/sh
# Builds Gleaner.app into build/ (release, ad-hoc signed for local use).
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product Gleaner
app=build/Gleaner.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Gleaner "$app/Contents/MacOS/Gleaner"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Gleaner</string>
  <key>CFBundleDisplayName</key><string>Gleaner</string>
  <key>CFBundleIdentifier</key><string>app.gleaner.Gleaner</string>
  <key>CFBundleExecutable</key><string>Gleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "$app"
