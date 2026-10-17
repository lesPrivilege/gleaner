#!/bin/sh
# Tests, builds and zips Gleaner.app into build/Gleaner-<version>.zip with a sha256 beside it.
# The app is ad-hoc signed; notarizing it needs a Developer ID and is done separately.
set -eu
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain)" ]; then
  echo "release: the working tree has uncommitted changes; commit them first" >&2
  exit 1
fi
swift test
./scripts/bundle-app.sh
app=build/Gleaner.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
zip="build/Gleaner-$version.zip"
rm -f "$zip" "$zip.sha256"
ditto -c -k --keepParent "$app" "$zip"
(cd build && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "$zip"
cat "$zip.sha256"
