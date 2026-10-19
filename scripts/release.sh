#!/bin/sh
# Tests, builds and zips Gleaner.app into build/Gleaner-<version>-<arch>.zip, with its sha256 and a
# manifest beside it. Ad-hoc signed by default; set GLEANER_SIGN_IDENTITY and GLEANER_NOTARY_PROFILE
# to sign with a Developer ID and notarize (docs/release.md). Publishing is scripts/publish.sh.
set -eu
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain)" ]; then
  echo "release: the working tree has uncommitted changes; commit them first" >&2
  exit 1
fi
swift test
./scripts/bundle-app.sh
app=build/Gleaner.app
plist="$app/Contents/Info.plist"
short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
display=$(/usr/libexec/PlistBuddy -c 'Print :GleanerDisplayVersion' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
min_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
# The architectures the binary holds, as lipo reads them: one names the zip, two or more are universal.
archs=$(lipo -archs "$app/Contents/MacOS/Gleaner")
case "$archs" in *' '*) arch=universal ;; *) arch=$archs ;; esac
name="Gleaner-$display-$arch"
zip="build/$name.zip"
rm -f "$zip" "$zip.sha256" "build/$name.json"
ditto -c -k --keepParent "$app" "$zip"
notarized=false
# GLEANER_NOTARY_PROFILE names a keychain profile made once with
# `xcrun notarytool store-credentials`; the zip is submitted, the ticket stapled to the app, and
# the app zipped again so the download carries the ticket.
if [ -n "${GLEANER_NOTARY_PROFILE:-}" ]; then
  case "$display" in *-dev*)
    echo "release: $display is not a tagged release; tag the commit (git tag v0.1.0) before notarizing" >&2
    exit 1 ;;
  esac
  if [ -z "${GLEANER_SIGN_IDENTITY:-}" ]; then
    echo "release: notarizing needs GLEANER_SIGN_IDENTITY (a Developer ID Application identity)" >&2
    exit 1
  fi
  xcrun notarytool submit "$zip" --keychain-profile "$GLEANER_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl --assess --type execute --verbose "$app"
  notarized=true
fi
codesign --verify --strict --verbose=2 "$app"
signing=$(codesign -dv "$app" 2>&1)
team=$(echo "$signing" | sed -n 's/^TeamIdentifier=//p')
case "$team" in ''|'not set') team=null; identity='"ad-hoc"' ;; *) team="\"$team\""; identity="\"${GLEANER_SIGN_IDENTITY:-}\"" ;; esac
case "$signing" in *'flags=0x10000(runtime)'*|*'(runtime)'*) runtime=true ;; *) runtime=false ;; esac
# The checksum last, of the zip that ships.
(cd build && shasum -a 256 "$name.zip" > "$name.zip.sha256")
sha=$(cut -d' ' -f1 "$zip.sha256")
tag=$(git describe --tags --exact-match --match 'v*' 2>/dev/null || true)
library=$(sed -n 's/.*static let extractorVersion = \([0-9]*\).*/\1/p' Sources/GleanerCore/Registry.swift)
# What was built, from what, and what was checked: facts this script saw, never claims. A person's
# check of the downloaded app is recorded as pending until they make it.
cat > "build/$name.json" <<JSON
{
  "schema": 1,
  "source_sha": "$(git rev-parse HEAD)",
  "tag": $( [ -n "$tag" ] && echo "\"$tag\"" || echo null ),
  "display_version": "$display",
  "short_version": "$short",
  "build": $build,
  "bundle_identifier": "$bundle_id",
  "architecture": "$arch",
  "architectures": "$archs",
  "minimum_macos": "$min_os",
  "built_on": { "macos": "$(sw_vers -productVersion)", "machine": "$(uname -m)", "swift": "$(swift --version 2>&1 | head -1 | sed 's/"/\\"/g')" },
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "asset": { "name": "$name.zip", "bytes": $(stat -f %z "$zip"), "sha256": "$sha" },
  "signing": { "identity": $identity, "team_id": $team, "hardened_runtime": $runtime },
  "notarized": $notarized,
  "tests": "swift test passed",
  "native_acceptance": "pending",
  "library_version": $library
}
JSON
echo "$zip"
cat "$zip.sha256"
