# Compact native acceptance for Opus / owner

Repository files and code citations use the pinned [source-location convention and file index](source-locations.md); `probes/` paths are relative to this review package.

Run on macOS 15+ in a disposable local test account with no private agent history. These are proposed checks, not results from this Linux review. Capture the unchanged UI before judging visual issues, then inspect the actual screenshots. Record OS/app/receiver versions and the tested commit.

## Set up synthetic inputs

Use a clean checkout pinned to the audited commit (or record the repaired commit). The following commands are for the Mac owner; none were run here:

```sh
git rev-parse HEAD
swift test
./scripts/bundle-app.sh
file build/Gleaner.app/Contents/MacOS/Gleaner
```

Copy the review's `probes` directory onto that Mac. Choose a new empty fixture directory, then run:

```sh
AUDIT_FIXTURE_ROOT=$(mktemp -d /tmp/gleaner-acceptance.XXXXXX)
python3 probes/make_fixtures.py "$AUDIT_FIXTURE_ROOT" initial
# Only in the disposable account: install this generated log, not real history.
mkdir -p "$HOME/.claude/projects/gleaner-audit"
cp "$AUDIT_FIXTURE_ROOT/audit.jsonl" "$HOME/.claude/projects/gleaner-audit/audit.jsonl"
open build/Gleaner.app
```

Wait for initial indexing. Save baseline hashes/permissions of regular fixture files (do not read `pipe.txt`, which is intentionally a FIFO). The first phase contains CJK Markdown, PNG, a symlink, a 65 MiB sparse file, truncated-preview text, and HTML with a sibling image. It does not pretend to contain a valid MP4 or PDF; add genuine fixed synthetic samples produced by an available local app before the receiver matrix.

After confirming D1 is captured, append a second delivery:

```sh
python3 probes/make_fixtures.py "$AUDIT_FIXTURE_ROOT" second
cp "$AUDIT_FIXTURE_ROOT/audit.jsonl" "$HOME/.claude/projects/gleaner-audit/audit.jsonl"
```

After D2 is captured, modify only current files, without a new delivery:

```sh
python3 probes/make_fixtures.py "$AUDIT_FIXTURE_ROOT" changed
```

The `changed` phase also replaces `replace.txt` with a directory containing unrelated text, solely inside this disposable fixture root. Use that case to verify D1. Synthetic fixture files are the only files whose contents/permissions should be altered during these checks.

## Acceptance sequence

1. **Search and recognition.** Search “recovery” → D1; “board” → D2; “recovery board” → no combined-history match. Query changes reset explicit version choice. Distinguish no matches, no sources, first scan, empty, partial failure. Check same-name files in two separately named and two same-named repositories. Delete an external linked worktree, quit/relaunch, and confirm its historical project context remains correct or explicitly unresolved.
2. **Selected bytes survive source changes.** After phase `changed`, choose old `guide.md` and `diagram.png` deliveries; preview/Open/tile/Copy must still yield their saved bytes. `replace.txt` must yield the saved regular file, not the directory. A missing selected folder must be unavailable. Selecting `pipe.txt` must never block or hash it. Verify symlink target permissions and bytes remain unchanged; two filenames sharing bytes both remain usable.
3. **Comparison.** Compare D1/D2 CJK Markdown, PNG D1/D2 and each against changed current bytes. Repeatedly rewrite the synthetic current PNG while comparison loads; pixels must correspond to the named digest or the comparison must refuse. Switch slow/fast comparison pairs before completion; stale results must not appear under new headers. Backfilled copies retain “first seen later.” Try a real PDF >64 KB, binary data, oversized text, line-ending-only changes and invalid UTF-8; limitation/fallback wording must be accurate, with no partial diff claimed complete.
4. **Quick Look and secondary navigation.** Space opens/closes; ⌘Y works. While the panel is open, switch D1→D2 and change a query that changes the matched delivery. Panel, tile and Copy stay coupled, or the panel closes deliberately. From a D1 “Delivered with” link, open its sibling's D1 even if that sibling has D2. Escape restores useful focus; right-clicking an unselected row affects that row.
5. **Preparation and cache lifecycle.** Use a sufficiently slow large copy (a synthetic file on a separate volume if available), switch A→B→A, and initiate row drag while detail staging is active. Never show another name/version or return a deleted staged file. Clear handoff copies while idle and during preparation; the selected item becomes ready again without reselecting. Copy a file, delay paste, then clear caches: verify the chosen retention behavior. Saved objects/capture associations survive all cache clears.
6. **Transfer matrix.** For each supported cell below, test both tile and row drag and list ⌘C/paste where the receiver offers file paste. Record accepted attachment/upload, correct original filename/extension and SHA-256 of bytes at the destination when retrievable. Otherwise inspect recognizable content and explicitly mark hash confirmation unavailable. A drag animation is not a pass. Original source path, bytes, permissions and existence stay unchanged; test Finder copy semantics for live folders separately.

| Payload | Finder | Claude Desktop | Codex | Browser upload |
|---|---|---|---|---|
| Markdown / genuine PDF | pending | pending | pending | pending |
| Genuine MP4 / PNG | pending | pending | pending | pending |
| Standalone HTML | pending | pending | pending | pending |
| Dependency-bearing HTML / live folder | pending; limitations visible | record supported/rejected | record supported/rejected | record supported/rejected |
| >64 MiB file / same hash with two names | pending | record size limits | record size limits | record size limits |

Unsupported receiver formats can be documented limits rather than product defects. Do not imply a single HTML file includes its siblings. Cancel a transfer and verify no source movement/deletion.

7. **Failure recovery.** In the disposable account, deny enumeration of the synthetic log folder, restore it, and Retry. Add an unknown record and a malformed replacement of a previously captured record. UI reports incomplete coverage and retains committed delivery/capture links. Make the original unreadable, preserving an existing saved copy; state must distinguish denied access from lost content. Check Save a Copy failure and Open failure feedback. Test the Git restore suggestion for a file added only on another branch and for apostrophes/spaces; do not run it outside a synthetic repository.
8. **Keyboard and VoiceOver.** Full Keyboard Access on: Find/search, Tab/Shift-Tab, list arrows, version buttons, disclosure, Compare, Open, Copy, Settings and recovery are reachable. Search accepts spaces and CJK marked-text composition; evidence-text ⌘C copies text while list ⌘C copies the exact file. VoiceOver announces filename, project, selected delivery, availability/provenance and preparation/failure changes meaningfully. It should not announce a drag affordance as the only path to takeaway.
9. **Appearance and scaling.** Inspect screenshots in light/dark, Increase Contrast, larger text/display scaling, reduced motion, narrow/minimum practical window and long CJK names/requests. Check wrapping/truncation, focus visibility and contrast. Do not infer failure from source font sizes alone. Preview restrictions and unavailable states remain visible without opening Details.
10. **Window/source lifecycle and scale.** Close, Hide, Minimize, Dock activation, Finder relaunch, Quit/relaunch and sleep/wake. Search/filters restore as intended, no duplicate indexing/windows, and watching behavior is explicit. Install/recreate an initially absent synthetic source while open; verify recovery. Measure first/cached scans, peak memory, input responsiveness and large-store Settings/Clear cost before requiring performance architecture changes.
11. **Distribution, owner only.** Test the actual downloaded release archive on a clean Mac using its intended architecture(s), macOS version and quarantine state. Verify signature, staple/notarization and Gatekeeper outcome appropriate to the announced release; validate version/About/icon/help and replacement install preserving the existing library. Follow `docs/release.md` for owner-controlled release steps. Update README/README.zh-CN/CHANGELOG to describe the actual signing state. No Sparkle/Homebrew requirement for v0.1.

## Optional focused core regressions

In a disposable copy of the checkout, copy `probes/AuditRegressionTests.swift` into `Tests/GleanerCoreTests/` and run `swift test --filter AuditRegressionTests`. Four baseline expectations are intentionally written for the desired repaired behavior and are expected to fail on the audited source. They have not been compiled here; first distinguish fixture/compile issues from product assertion failures. Keep the release checkout clean and do not commit these tests automatically.

Record each result as pass / fail / unsupported / not tested with commit, fixture phase, exact target version/hash and screenshot where useful. Once the targeted checks pass, no broader rewrite or repeated full matrix is justified without a new change or failure.
