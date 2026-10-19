#!/bin/sh
# Builds Gleaner.app into build/ (release build; signing as below).
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product GleanerApp

# The version is the tag on HEAD: v0.1.0, or a candidate's v0.1.0-rc.1. CFBundleShortVersionString
# holds its three numbers (0.1.0); the whole of it, the display version, is GleanerDisplayVersion and
# names the zip. Untagged builds are the release in progress plus the commit: 0.1.0-dev+1a2b3c4.
release=0.1.0
if tag=$(git describe --tags --exact-match --match 'v*' 2>/dev/null); then
  display=${tag#v}
  short=${display%%-*}
  if ! echo "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    echo "bundle-app: tag $tag is not vX.Y.Z or vX.Y.Z-<candidate> (v0.1.0, v0.1.0-rc.1)" >&2
    exit 1
  fi
else
  short=$release
  display="$release-dev+$(git rev-parse --short HEAD)"
fi
# The build number only goes up across every published build: by default the commits on main's
# first-parent line to HEAD, which a shallow clone can't count. GLEANER_BUILD sets it instead;
# scripts/publish.sh refuses one not above every published build.
if [ -n "${GLEANER_BUILD:-}" ]; then
  build=$GLEANER_BUILD
else
  if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    echo "bundle-app: a shallow clone can't count the build number; fetch with --unshallow or set GLEANER_BUILD" >&2
    exit 1
  fi
  build=$(git rev-list --count --first-parent HEAD)
fi
case "$build" in ''|*[!0-9]*)
  echo "bundle-app: the build number must be a positive integer, not '$build'" >&2
  exit 1 ;;
esac
app=build/Gleaner.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/GleanerApp "$app/Contents/MacOS/Gleaner"
# The notices for the drawings the app carries.
mkdir -p "$app/Contents/Resources"
cp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/THIRD-PARTY-NOTICES.md"
# The owner's icon, when there is one: Resources/AppIcon.icns.
icon=""
if [ -f Resources/AppIcon.icns ]; then
  mkdir -p "$app/Contents/Resources"
  cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
  icon="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi
# CFBundleURLTypes: a gleaner://delivery/<id> link opens the app on that delivery.
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
  <key>CFBundleShortVersionString</key><string>$short</string>
  <key>GleanerDisplayVersion</key><string>$display</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 lesPrivilege</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>app.gleaner.Gleaner.delivery</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleURLSchemes</key><array><string>gleaner</string></array>
    </dict>
  </array>
  <!-- A work dragged from a list onto a collection, read only by Gleaner. -->
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>app.gleaner.work</string>
    <key>UTTypeDescription</key><string>Gleaner work</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
  </dict></array>
  $icon
</dict>
</plist>
PLIST
# GLEANER_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" signs for distribution with the
# hardened runtime and a secure timestamp; without it the app is ad-hoc signed for local use.
if [ -n "${GLEANER_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$GLEANER_SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
fi
echo "$app $display ($build, $(lipo -archs "$app/Contents/MacOS/Gleaner"))"
