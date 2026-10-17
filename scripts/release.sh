#!/bin/sh
# Tests, builds and zips Gleaner.app into build/Gleaner-<version>.zip with a sha256 beside it.
# Ad-hoc signed by default; set GLEANER_SIGN_IDENTITY and GLEANER_NOTARY_PROFILE to sign with a
# Developer ID and notarize (docs/release.md).
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
# GLEANER_NOTARY_PROFILE names a keychain profile made once with
# `xcrun notarytool store-credentials`; the zip is submitted, the ticket stapled to the app, and
# the app zipped again so the download carries the ticket.
if [ -n "${GLEANER_NOTARY_PROFILE:-}" ]; then
  case "$version" in *-dev*)
    echo "release: $version is not a tagged release; tag the commit (git tag v0.1.0) before notarizing" >&2
    exit 1 ;;
  esac
  if [ -z "${GLEANER_SIGN_IDENTITY:-}" ]; then
    echo "release: notarizing needs GLEANER_SIGN_IDENTITY (a Developer ID Application identity)" >&2
    exit 1
  fi
  xcrun notarytool submit "$zip" --keychain-profile "$GLEANER_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl --assess --type execute --verbose "$app"
fi
(cd build && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "$zip"
cat "$zip.sha256"
