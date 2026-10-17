# Releasing Gleaner

The path from a green `main` to a downloadable, notarized `Gleaner-0.1.0.zip`. Steps marked **owner** need the owner's Apple Developer account or judgment and cannot be done by an agent.

## 1. Before tagging

- [ ] `swift test` passes on `main`.
- [ ] **owner** App icon: put `AppIcon.icns` in `Resources/`; `scripts/bundle-app.sh` picks it up. Until then the app shows the generic icon.
- [ ] Manual checks on a build from `./scripts/bundle-app.sh`, in light and dark appearance:
  - drag the hand-off tile, and a result row, into Finder, Claude Desktop, Codex and a browser upload field;
  - ⌘C in the list, then paste into Finder and into an agent's composer;
  - Space and ⌘Y open Quick Look on the selection; picking another delivery or changing the search closes it unless the same bytes stay selected; Space again closes it;
  - right-click a result: each item acts on that result;
  - Compare two deliveries, an image pair, and a delivery against a changed file on disk;
  - a file under "Delivered with" opens on its delivery from that reply;
  - Settings shows how each log folder read and Read Again rereads them; clearing hand-off copies prepares the selection's copy again;
  - VoiceOver reads a result row, a delivery row and the drag tile as one sentence each;
  - quit and relaunch: search and filters come back.
- [ ] `CHANGELOG.md`: give 0.1.0 its date.

## 2. Tag

```bash
git tag v0.1.0
```

A tagged commit builds as `0.1.0`; untagged builds read `0.1.0-dev+<commit>`.

## 3. Sign and notarize (**owner**)

Once per Mac, store notary credentials in the keychain (an app-specific password or an App Store Connect API key; nothing is written to the repository):

```bash
xcrun notarytool store-credentials gleaner-notary
```

Then build, sign with the hardened runtime, notarize, staple and zip:

```bash
GLEANER_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" GLEANER_NOTARY_PROFILE=gleaner-notary ./scripts/release.sh
```

The script refuses a dirty tree, refuses to notarize an untagged build, runs the tests, and ends with a Gatekeeper assessment of the stapled app. It writes `build/Gleaner-0.1.0.zip` and its `.sha256`.

Without the two variables it produces an ad-hoc signed zip for local testing. On another Mac, macOS 15 refuses it the first time; it opens after System Settings → Privacy & Security → Open Anyway.

## 4. Publish (**owner**)

```bash
git push origin v0.1.0
gh release create v0.1.0 build/Gleaner-0.1.0.zip build/Gleaner-0.1.0.zip.sha256 --title "Gleaner 0.1.0" --notes-file <(sed -n '/## 0.1.0/,/^## /p' CHANGELOG.md | sed '$d')
```

A Homebrew cask and in-app updates (Sparkle) come after the first release (SPEC §15).

## What is not in 0.1.0

The limits users meet are listed in the README. Design work queued after release: Thread, Outline, Project timeline (`docs/design/structure.md`).
