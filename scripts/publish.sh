#!/bin/sh
# Publishes the build of the tag on HEAD as a draft GitHub release: the zip, its sha256 and its
# manifest from scripts/release.sh. The owner checks the draft and publishes it on GitHub.
# A published asset is never replaced: a release that exists already is refused, and so is a build
# number not above every published one. A new build needs a new tag (v0.1.0-rc.2).
set -eu
cd "$(dirname "$0")/.."
tag=$(git describe --tags --exact-match --match 'v*' 2>/dev/null) || {
  echo "publish: HEAD has no release tag; tag it (git tag v0.1.0-rc.1) and run scripts/release.sh" >&2
  exit 1
}
head=$(git rev-parse HEAD)
manifest=""
for candidate in build/Gleaner-"${tag#v}"-*.json; do
  [ -f "$candidate" ] || continue
  [ "$(plutil -extract source_sha raw -o - "$candidate")" = "$head" ] && manifest=$candidate
done
if [ -z "$manifest" ]; then
  echo "publish: no manifest in build/ for $tag at $head; run scripts/release.sh" >&2
  exit 1
fi
name=$(plutil -extract asset.name raw -o - "$manifest")
build=$(plutil -extract build raw -o - "$manifest")
zip="build/$name"
# The zip is the one the manifest describes.
if [ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$(plutil -extract asset.sha256 raw -o - "$manifest")" ]; then
  echo "publish: $zip doesn't match its manifest; run scripts/release.sh again" >&2
  exit 1
fi
if gh release view "$tag" >/dev/null 2>&1; then
  echo "publish: a release for $tag exists already; its assets are never replaced. Tag a new build." >&2
  exit 1
fi
# Every published build's number, from its manifest.
seen=$(mktemp -d)
trap 'rm -rf "$seen"' EXIT
for published in $(gh release list --limit 200 --json tagName --jq '.[].tagName'); do
  gh release download "$published" --pattern 'Gleaner-*.json' --dir "$seen/$published" 2>/dev/null || continue
  for other in "$seen/$published"/*.json; do
    before=$(plutil -extract build raw -o - "$other")
    if [ "$build" -le "$before" ]; then
      echo "publish: build $build is not above $published's build $before; set GLEANER_BUILD above it and run scripts/release.sh" >&2
      exit 1
    fi
  done
done
case "$tag" in *-*) prerelease=--prerelease ;; *) prerelease= ;; esac
git push origin "refs/tags/$tag"
notes=$(mktemp)
short=$(plutil -extract short_version raw -o - "$manifest")
awk -v heading="## $short" 'index($0, heading) == 1 {f=1; next} /^## /{f=0} f' CHANGELOG.md > "$notes"
gh release create "$tag" "$zip" "$zip.sha256" "$manifest" --draft $prerelease --verify-tag \
  --title "Gleaner ${tag#v}" --notes-file "$notes"
rm -f "$notes"
echo "publish: draft release $tag made; check its assets on GitHub, then publish it"
