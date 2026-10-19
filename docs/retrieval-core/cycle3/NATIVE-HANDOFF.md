# Native CI receipt and proposed M1–M5 diagnostics

**Status: native package build and full `swift test` executed in hosted CI;
the additional M1–M5 diagnostic probe has not run natively.**
[Run 39277126786, job 118144332343](https://github.com/lesPrivilege/gleaner/actions/runs/39277126786/job/118144332343)
checked out `24811b063eba4885822001f68e5655dfd83d079e` and built successfully
(172.15 seconds) on macOS 26.6.2, build 25G83, image `macos-26-arm64`.
The Swift Testing run executed **528 tests in 51 suites**, finishing with
**16 issues, all in the experimental `OriginalResolutionTests`**, after 37.954
seconds. All other executed tests passed, including all 19 existing tests selected below
for M1–M5. The earlier XCTest banner reporting zero tests is not the full result.

This receipt establishes native compilation and the reported test outcomes at
that SHA, not success of subsequent edits. The log does not report the exact
Swift compiler version; `Testing Library Version: 1902` is not that version.
The probe's native linking path, detailed filesystem/SQLite diagnostics and
optional case-sensitive-volume comparison remain unexecuted.

The repaired source `6a39a13e6929bc7ab1ac24700a0af0929ad2bf44` and identical-code
checkpoint `3ea45fdaaf9c67d5669c7150da4882a71b63adb9` now have completed native
test logs: **541 enumerated tests / 55 suites, 535 passed, six skipped, zero failures**.
All 19 M1–M5 selected existing tests pass again. The
[successor receipt](NATIVE-CI-RECEIPT.md) records exact jobs, log hashes and the
run-status metadata discrepancy. These passes do not run the extra diagnostic
probe or establish native root-alias compatibility for core-produced locators.

The remaining handoff requires a separate runner/access decision and is not
permission to use the user's Mac. At execution, the parent must supply the exact
approved delivery SHA; never substitute moving `main`.

## Runner and access decision

Authorize a named disposable macOS VM/runner and ordinary, non-root test account,
or explicitly approve another Mac with the same isolation. No personal home,
Praxis checkout, existing Gleaner library, or real Claude/Codex logs should be mounted
into a disposable runner. The following access is sufficient:

| Resource | Required access |
|---|---|
| New detached checkout, its `.build`, task caches and result directory | Read/write, disposable; no existing repository changes |
| New synthetic fixture subtree within the account's native temporary directory | Read/write; tests create files, Git fixtures, SQLite databases and permission fixtures |
| Compiler/system caches belonging to the disposable test account | Runtime writes; task cache flags are not a filesystem sandbox |
| Installed compiler, SDK/frameworks, Git, Python and SQLite | Read/execute |
| `/tmp`, `/var`, `/private`, `/Users`, current-home path | Metadata/path checks only; no enumeration of personal content |
| Public repository and pinned package sources | Network download if not already cached; no new credentials |

The fixtures explicitly pass synthetic `home`, log-source and registry paths.
**Do not replace `HOME`**: `NSHomeDirectory()` is used to test exclusion of the real
home. No app launch, normal-home `gleaner-index`, signing, release scripts, updater,
main merge, workflow change or push is needed. Do not install/update toolchains or
change global Git settings as an implicit part of this handoff.

Runtime: package deployment target macOS 15+, native Xcode SDK/frameworks, Git,
Python 3, and **Swift 6.2 or newer** for the current pins. The root manifest says
6.0, but pinned `swift-log` and the applicable `swift-collections` manifest require
6.2. Linux measured 6.2.4; the native CI receipt above establishes compilation on
its macOS 26.6.2 ARM64 image but does not identify its exact compiler version.
Record the actual Mac/Xcode/Swift pair for the diagnostic run.
`swift test --filter` may compile native app/UI targets even
though the commands below execute only selected core tests.
The account/VM boundary provides isolation; path flags alone cannot give an
existing personal account the same isolation. The probe invokes `swiftc` on
`PATH`: it must match the `swift` used to build the core and the selected SDK.

## Preparation and commands

Run these only after the runner, revision, temporary parent and write scope above
are approved. Use an ordinary shell without `sudo`; keep failures and exit codes.
The temporary parent should have the normal short `/var/...` spelling: existing
M3 tests assume Foundation's native `/var` to `/private/var` alias layout. If that
precondition is absent, record it; do not manufacture `/private` or alter a volume.

```sh
sw_vers
xcodebuild -version
xcrun swift --version
xcrun --show-sdk-version
command -v swift swiftc
swift --version
swiftc --version
git --version
python3 --version
sqlite3 --version
id -u
getconf DARWIN_USER_TEMP_DIR

gleaner_revision='<parent-approved 40-character commit SHA>'
gleaner_native_temp="$(getconf DARWIN_USER_TEMP_DIR)"
gleaner_handoff_root="$(mktemp -d "${gleaner_native_temp%/}/gleaner-native-handoff.XXXXXX")"
mkdir -p "$gleaner_handoff_root/fixtures" "$gleaner_handoff_root/results"
env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
  git clone --no-checkout https://github.com/lesPrivilege/gleaner "$gleaner_handoff_root/repo"
env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
  git -C "$gleaner_handoff_root/repo" checkout --detach "$gleaner_revision"
cd "$gleaner_handoff_root/repo"
git rev-parse HEAD
git status --short
```

Use Bash for this helper. It keeps dependency/configuration caches in the new task
root, ignores personal/system Git configuration for fixture subprocesses, and
returns the actual test exit code. It does not change test expectations.
Resolve a compiler/SDK mismatch before building; do not change global
`xcode-select` settings to fix it as part of this handoff.

```bash
gleaner_native_test() {
  local check="$1" filter="$2" result
  env TMPDIR="$gleaner_handoff_root/fixtures/" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    SWIFTPM_MODULECACHE_OVERRIDE="$gleaner_handoff_root/module-cache" \
    swift test -j 4 \
      --cache-path "$gleaner_handoff_root/package-cache" \
      --config-path "$gleaner_handoff_root/package-config" \
      --security-path "$gleaner_handoff_root/package-security" \
      --force-resolved-versions --filter "$filter" \
      > "$gleaner_handoff_root/results/$check.log" 2>&1
  result=$?
  printf '%s\n' "$result" > "$gleaner_handoff_root/results/$check.status"
  return "$result"
}

gleaner_native_test M1 'ObservationTests/(aVideoSeriesWhoseReplyNamesOnlyAFolder|aReportWithMarkdownPDFAndCharts|aDataAnalysisWithCSVFiguresAndANotebook|aLaterSessionEditingAFileAddsItsOwnObservation|aHandedOverFileKeepsItsDeliveryWithItsObservationBeside|theSyntheticHomesCapturePhase)|BundleTests/(aMediaPipelineHandsOverItsSegmentsButNeverItsHiddenFiles|aFolderDeliveredTwiceListsItsFilesAtEachDelivery|membershipByTimeOnALiveRead)|KeepTests/keepingMakesAWorkWhoseOneRevisionIsTheFileAsObserved|ReviewTests/aRewriteInPlaceThatPutsTheDatesBackIsNotAsShown'
gleaner_native_test M2 'ObservationTests/(aFileNamedInAnotherSpellingIsObservedUnderItsDeliveredName|aFolderIsSkippedHoweverItIsSpelled)'
gleaner_native_test M3 'ProjectTests/(aFolderUnderPrivateIsOneProjectWithWhatItsAgentDelivered|aFolderUnderPrivateVarIsOneProjectWithItsFilesThereOrGone)|ObservationTests/theHomeFolderAndSystemFoldersAreNotWalked'
gleaner_native_test M4 'ObservationTests/aBuiltAppIsObservedAsOneEntry|BundleTests/aPackageInADeliveredFolderIsOneOfItsFiles'
gleaner_native_test M5 'CatalogTests/aLibraryThatCantBeOpenedToReadSaysToOpenGleaner'
```

Run each independently and retain failures without preventing the probe.
M5's original assertion passed in the recorded native run; do not assume the
Linux failure will recur. A compiler, SDK, dependency-pin or linking failure is a **setup blocker**,
not a test result. If forced resolution rejects platform-specific lock metadata,
return its error and original lockfile to the parent; do not silently update pins.
No sandbox-disabling flag is required by this handoff.

Once the real debug core has built, run the existing diagnostic:

```sh
env TMPDIR="$gleaner_handoff_root/fixtures/" \
  SWIFTPM_MODULECACHE_OVERRIDE="$gleaner_handoff_root/module-cache" \
  python3 eval/retrieval/cycle2/native/run.py --local --repository "$PWD" \
  --output "$gleaner_handoff_root/results/native-probe.json" \
  > "$gleaner_handoff_root/results/native-probe.log" 2>&1
printf '%s\n' "$?" > "$gleaner_handoff_root/results/native-probe.status"
git status --short
git diff -- Package.resolved
```

The [runner](../../../eval/retrieval/cycle2/native/run.py) links existing
`.build/debug/GleanerCore.build` objects and does **not** rebuild the package. On
Mac it omits Linux Crypto/CSQLite objects, relies on native framework autolinking,
and creates its executable in a temporary directory. Its `--local` path has not
been executed on a Mac. A native linker failure must remain visible. A successful
probe records the checked-out SHA and probe-source hash, not proof that stale
objects match that SHA; hence the fresh checkout and successful build are required.

## What to decide from each result

All existing tests in this table passed in the native CI receipt. The additional
probe observations below remain to be measured; passing those tests does not
establish the separate mechanisms or limitations described here.

| Check | Existing tests versus additional probe | Expected observation and classification |
|---|---|---|
| **M1** Birth dates, membership, stale review | Eleven original tests; probe `birthtime`, `synthetic_future_birth`, `review_freshness` | Verify that requested birth dates actually took effect before expecting `appeared` or appendix membership only in the later reply. With unknown birth, preserve unknown and classify the affected assertion as a metadata/fixture dependency. Same-size rewrite must cause stale-approval refusal and zero reviews written; failure after valid setup is a core defect to investigate. |
| **M2** Case and symlinks | Two original tests; probe `case_and_alias` | On case-insensitive storage, alternate spelling identifies the same object. On case-sensitive storage it may be absent or a distinct object; do not merge by case alone. A real symlink to home/Library must be excluded. Case-assuming test failures on a case-sensitive volume are harness dependencies, not automatic product regressions. |
| **M3** Native aliases, roots, permissions | Three original tests; probe `system_paths`, `private_and_permissions` | Confirm the actual `/var` ↔ `/private/var` alias before interpreting identity assertions. A missing alias or fixture-creation EACCES is setup/layout evidence. A locked synthetic file should remain a locator `file` but deny readable stat/hash. `/Users` exclusion relies on home ancestry; these checks do not establish authorized-root safety for relocated homes or other users' data. |
| **M4** Packages | Two original tests; probe `packages` | Record native UTType classification and one-entry `.app`/`.rtfd` behavior; do not use the Linux extension table as native truth. If `package_metadata_unchanged_after_nested_file_rewrite` is true, metadata-only observation misses that edit: a confirmed limitation even if tests pass. Unexpected grouping with valid metadata requires investigation. |
| **M5** Read-only WAL | One original test, passed in native CI; probe `readonly_wal` | The native test passed its expected refusal; the log does not establish the sidecar/VFS mechanism. The separate clean-checkpoint probe distinguishes writable-parent opening/sidecar creation from unwritable-parent refusal, SQL write rejection and unchanged main bytes. Those were the Linux observations, not native measurements. Preserve native SQLite version, permissions and sidecar outcomes before interpreting divergence. Neither a native pass nor a Linux failure establishes corruption or universal refusal. Never remove a live WAL to test it. |

Optional M2 extension: only if an **existing, already authorized empty temporary
directory on case-sensitive APFS** is available, run the probe again with
`TMPDIR` set to that directory and a distinct output filename. It writes synthetic
fixtures there. No formatting, volume creation, mount changes or user-data-volume
configuration is authorized. Do not rerun M3's `/private`-assuming tests under an
external-volume `TMPDIR` and call their setup failure a core defect.

Return the exact revision, runtime metadata, test names/counts/statuses, probe JSON,
and any setup blockers. Keep raw logs in the disposable scratch area; sanitize
account names and machine-specific paths before public delivery. Do not publish
logs automatically. The interpretation baseline is
[NATIVE-FAILURES.md](../cycle2/NATIVE-FAILURES.md); successful M1–M5 results establish
only these native checks, not app usability, retrieval generalization or release
readiness. The native CI receipt above is actual execution; the separate diagnostic
probe and any access to another Mac remain pending.

The successor CI logs also pass the existing native
`aLogFolderCreatedAfterLaunchIsNoticedAndThenWatched` integration test and UI/model
unit suites. Remaining manual/rendered flows and end-to-end ingestion must not be
confused with those executed checks. The six skipped opt-in drawing/walk/measurement
tests are named in NATIVE-CI-RECEIPT.md.
