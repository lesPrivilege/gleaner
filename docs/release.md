# Releasing Gleaner

The path from a green `main` to a downloadable, notarized `Gleaner-0.1.0.zip`. Steps marked **owner** need the owner's Apple Developer account or judgment and cannot be done by an agent.

## 1. Before tagging

- [ ] `swift test` passes on `main`.
- [ ] **owner** App icon: put `AppIcon.icns` in `Resources/`; `scripts/bundle-app.sh` picks it up. Until then the app shows the generic icon.
- [ ] **owner** Make the docs say what will ship, since the tagged commit is what the zip is built from. Signing: if §3 will notarize this release, rewrite the ad-hoc install steps (Installation) and the "not notarized" limit (Limits in v0.1) in `README.md` and `README.zh-CN.md`, and the "ad-hoc signed, not notarized" known limit in `CHANGELOG.md`; if it won't, keep them. Icon: with `AppIcon.icns` in place, drop the "no icon" lines from the same three files.
- [ ] Manual checks on a build from `./scripts/bundle-app.sh`, in light and dark appearance, on a synthetic home that leaves your own library and agent history alone: `scripts/acceptance-home.py <home> initial`, then `open -n build/Gleaner.app --args -GleanerHome <home>`; the script describes its later phases.
  - drag the hand-off tile, and a result row, into Finder, Claude Desktop, Codex and a browser upload field;
  - drag a delivered folder's row into Finder: it is copied, and the original stays where it was;
  - ⌘C in the list, then paste into Finder and into an agent's composer;
  - Space and ⌘Y open Quick Look on the selection; picking another delivery or changing the search closes it unless the same bytes stay selected; Space again closes it;
  - right-click a result: each item acts on that result;
  - Compare two deliveries, an image pair, and a delivery against a changed file on disk;
  - a file under "Delivered with" opens on its delivery from that reply;
  - Sources (⌘,) shows how each log folder read and Read Again rereads them; Storage's Clear prepares the selection's copy again;
  - a project opens on its outline; Same Work, Not the Same, Move to Project…, Put Back and Show Apart act as their help says, survive a relaunch, and Your Corrections undoes each and Undo All all of them;
  - VoiceOver reads a result row, a delivery row and the drag tile as one sentence each;
  - quit and relaunch: search and filters come back.
- [ ] `CHANGELOG.md`: give 0.1.0 its date.

## 2. Tag (**owner**)

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

The script refuses a dirty tree, refuses to notarize an untagged build, runs the tests, and ends with a Gatekeeper assessment of the stapled app. It writes `build/Gleaner-0.1.0.zip` and its `.sha256`. If notarization fails and the ad-hoc zip ships instead, the docs must say so again (§1): fix them and tag again before publishing.

Without the two variables it produces an ad-hoc signed zip for local testing. On another Mac, macOS 15 refuses it the first time; it opens after System Settings → Privacy & Security → Open Anyway.

## 4. Publish (**owner**)

```bash
git push origin v0.1.0
gh release create v0.1.0 build/Gleaner-0.1.0.zip build/Gleaner-0.1.0.zip.sha256 --title "Gleaner 0.1.0" --notes-file <(awk '/^## 0\.1\.0/{f=1;next} /^## /{f=0} f' CHANGELOG.md)
```

The notes are every line of the 0.1.0 section of `CHANGELOG.md` below its heading, up to the next release's heading.

A Homebrew cask and in-app updates (Sparkle) come after the first release (SPEC §14, Distribution).

## What is not in 0.1.0

The limits users meet are listed in the README. Design work queued after release: Thread, Outline, Project timeline (`docs/design/structure.md`).
