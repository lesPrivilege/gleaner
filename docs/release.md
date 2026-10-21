# Releasing Gleaner

The path from a green `main` to a downloadable, notarized `Gleaner-0.1.0.zip`. Steps marked **owner** need the owner's Apple Developer account or judgment and cannot be done by an agent.

## 1. Before tagging

- [ ] `swift test` passes on `main`.
- [ ] **owner** App icon: put `AppIcon.icns` in `Resources/`; `scripts/bundle-app.sh` picks it up. Until then the app shows the generic icon.
- [ ] **owner** Make the docs say what will ship, since the tagged commit is what the zip is built from. Signing: if §3 will notarize this release, rewrite the ad-hoc install steps (Installation) in `README.md` and `README.zh-CN.md`, and the "ad-hoc signed, not notarized" limit, one line in both READMEs and `CHANGELOG.md`; if it won't, keep them. Icon: with `AppIcon.icns` in place, drop the "no icon" lines from the same three files.
- [ ] Manual checks on a build from `./scripts/bundle-app.sh`, in light and dark appearance, on a synthetic home that leaves your own library and agent history alone: `scripts/acceptance-home.py <home> initial`, then `open -n build/Gleaner.app --args -GleanerHome <home>`; the script describes its later phases.
  - drag the hand-off tile, and a result row, into Finder, Claude Desktop, Codex and a browser upload field;
  - drag a delivered folder's row into Finder: it is copied, and the original stays where it was;
  - ⌘C in the list, then paste into Finder and into an agent's composer;
  - Space and ⌘Y open Quick Look on the selection; picking another delivery or changing the search closes it unless the same bytes stay selected; Space again closes it;
  - right-click a result: each item acts on that result;
  - Compare two deliveries, an image pair, and a delivery against a changed file on disk;
  - a file under "Delivered With" opens on its delivery from that reply;
  - Sources (⌘,) shows how each log folder read and Read Again rereads them; Storage's Clear prepares the selection's copy again;
  - a project opens on its outline; Join, Keep Apart, Move to Project…, Put Back and Show Apart act as their help says, survive a relaunch, ⌘Z takes back a join, a keep-apart and a move, and Corrections undoes each and Undo All all of them;
  - the toolbar's Sources button opens the popover; each switch turns its agent off and on, hiding and showing its deliveries, and survives a relaunch; Codex through Magpie shows `magpie` and the model on its page;
  - each ⓘ opens its sentence by click and by keyboard; the sidebar's marks turn white on a focused selection and follow the sidebar icon size; the file at the top of the detail shows the grab pointer and drags;
  - VoiceOver reads a result row, a version row and the file at the top of the detail as one sentence each, and the agents' marks by name;
  - quit and relaunch: search and filters come back.
- [ ] `CHANGELOG.md`: give 0.1.0 its date. Its `## 0.1.0` section must cover everything the tagged commit builds: `publish.sh` takes the release notes from that section alone.

## 2. Tag (**owner**)

```bash
git tag v0.1.0-rc.1
```

A tag is `vX.Y.Z`, or a candidate's `vX.Y.Z-rc.N`. The app's `CFBundleShortVersionString` holds its three numbers (`0.1.0`); the whole tag minus the `v` is its display version (`GleanerDisplayVersion`), which names the zip. Untagged builds read `0.1.0-dev+<commit>`.

The build number (`CFBundleVersion`) only goes up across every published build. It counts the commits on main's first-parent line, so build from `main` in a full clone; `bundle-app.sh` refuses a shallow one. `GLEANER_BUILD=<n>` sets it instead. Each published package gets its own tag and build: a published one is never replaced, so a rebuild after notarization or a docs fix is the next candidate (`v0.1.0-rc.2`), never the same tag again.

## 3. Build, sign and notarize (**owner**)

Once per Mac, store notary credentials in the keychain (an app-specific password or an App Store Connect API key; nothing is written to the repository):

```bash
xcrun notarytool store-credentials gleaner-notary
```

Then build, sign with the hardened runtime, notarize, staple and zip:

```bash
GLEANER_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" GLEANER_NOTARY_PROFILE=gleaner-notary ./scripts/release.sh
```

The script refuses a dirty tree, refuses to notarize an untagged build, runs the tests, validates the stapled ticket, verifies the signature strictly and ends with a Gatekeeper assessment. It writes, under `build/`:

- `Gleaner-<display version>-<arch>.zip`, `arch` being what `lipo -archs` reads from the binary (`arm64` from an Apple Silicon Mac; `universal` for more than one);
- its `.sha256`, computed last, of the zip that ships;
- `Gleaner-<display version>-<arch>.json`, the manifest: source commit, tag, versions, build, bundle ID, architecture, minimum macOS, the Mac and Swift it was built with, the asset's size and hash, the signing identity, team and hardened runtime, whether it was notarized, the tests, the library version, and the native acceptance as `pending`. It records only what the script saw.

Without the two variables it produces an ad-hoc signed zip for local testing, with `"notarized": false`. On another Mac, macOS 15 refuses it the first time; it opens after System Settings → Privacy & Security → Open Anyway. If an ad-hoc build ships instead of a notarized one, the docs must say so (§1).

## 4. Publish (**owner**)

```bash
./scripts/publish.sh
```

It finds the manifest of the tag on HEAD, checks the zip against it, and refuses when a release for the tag exists already or when the build number isn't above every published release's manifest. Then it pushes the tag and makes a **draft** release (a prerelease for a candidate tag) with the zip, its `.sha256` and the manifest, its notes the version's section of `CHANGELOG.md`. Check the draft's assets on GitHub, then publish it there.

After publishing, download the zip from the release, install it in `/Applications`, and run the §1 checks on that copy, not on a local build; record the result beside the manifest.

## Library backups

Before a Gleaner updates a library an earlier version left, it copies `registry.sqlite` whole to `Backups/registry-v<version>-<time>.sqlite` in `~/Library/Application Support/Gleaner/`, and changes nothing if the copy fails. Saved bytes (`objects/`) aren't copied: they are kept by hash and never rewritten. To go back to the earlier Gleaner, quit Gleaner, move `registry.sqlite` and its `-wal` and `-shm` files aside, and copy the backup in as `registry.sqlite`. Gleaner never removes a backup.

A Homebrew cask and in-app updates (Sparkle) come after the first release (SPEC §14, Distribution).

## What the candidate holds

The candidate is built from main and holds all of it: a project's outline, and Thread, a Markdown file's Contents and Project timeline, which `docs/design/structure.md` once queued for after release. The zip holds the app; the `gleaner` command and `gleaner mcp` are built from source (README). The limits users meet are listed in the README.
