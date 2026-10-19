# Eighteen shared failures: independent diagnosis

The baseline's 324-test run and checkpoint's 346-test run have exactly the same
18 failing tests and 25 issues. They are **not collectively excused as Linux
failures**: nine are explained by unavailable birth-time evidence, eight depend
on filesystem/test-fixture assumptions, and one exposes a false read-only WAL
contract assumption. No production code, assertion, or skip list was changed in
this investigation. The original full-run failures remain recorded.

Baseline: `2648094610facfd1ae1805f52a9de282043c808f` plus the preserved portability
patch. Candidate checkpoint: `7e004a72920d0648c8d7ce38bdb4da86eab4926c`.
Full detail, exact assertion locations, log digests, uncertainties and source
references are in [native-failure-classifications.json](native-failure-classifications.json).

The diagnostic [NativeProbe.swift](../../../eval/retrieval/cycle2/native/NativeProbe.swift)
was linked directly against each checkout's existing compiled shared-core objects.
It ran as UID1000 with synthetic temporary files. It did not rebuild or modify the
package. [Baseline](native-probe-baseline.json) and
[candidate](native-probe-candidate.json) measurements agree on the behaviors below;
timestamps differ. These probes are additional diagnostics, not passing replacements
for the failing tests.

## Runtime evidence

**Birth time.** The Linux compatibility layer deliberately supplies unknown birth
time to the core. Setting Foundation `.creationDate` returned without error but
did not install the requested timestamp. Foundation subsequently reported the
inode change time as creation time, matching the
[Swift 6.2.4 Foundation source](https://github.com/swiftlang/swift-foundation/blob/swift-6.2.4-RELEASE/Sources/FoundationEssentials/FileManager/FileManager%2BFiles.swift).
The core kept `createdAt=nil`. Actual `Workspace.place` returned `changed`; a
clearly marked counterfactual input with known birth returned `appeared`. This
explains the nine kind failures without inventing creation evidence. It does not
prove authorship or exhaustive capture.

**Fixture chronology.** The two-delivery fixture creates both files before two
future reply times, then tries to assign the appendix a future birth date. That
assignment is ineffective here. Actual ctime precedes both replies, so
`Membership.handedOver` returns true for both. Providing the intended known birth
makes the first membership false. In the live move/link/copy test, three failing
assertions inspect Foundation's ctime-backed creation attribute; the final
membership checks report no failure. Those failures must not be described as
measured incorrect real chronology without a valid lifecycle fixture.

**Review protection.** The original rewrite test aborts at `#require(createdAt)`
before checking approval. A separate same-size rewrite probe restores the original
whole-second modification timestamp and calls the actual indexer: persisted-state
comparison is equal, immediate freshness is false, stale approval is rejected,
and zero review records are written. This checks the previously unreached Linux
path; it does not execute the native test.

**Identity and permissions.** Wrong-case spelling does not exist on this volume;
creating both spellings gives different file identities. A real symlink to home is
excluded correctly. The uppercase-home string is not a real alias and is not
excluded as home. Case sensitivity is a volume property: Apple also supports
[case-sensitive APFS](https://support.apple.com/guide/disk-utility/file-system-formats-dsku19ed921c/mac).
The container has no `/private`, `/tmp` resolves to itself, and UID1000 cannot create
root directories. A separate `chmod 000` probe confirms that locator metadata still
reports a file while readable `FileStat` and hashing refuse access.

**System roots.** `/Users` is the sole nil exclusion in the failing system-path
loop. It does not exist here and is neither a supplied-home nor real-home ancestor;
there is no explicit `/Users` rule. `Workspace.root` rejects nonexistent folders
before walking. This run therefore did not scan that path, but exclusion of an
existing users root with a relocated current home is not guaranteed by the rule.

**WAL.** With cleanly checkpointed sidecar-free fixtures, `Catalog` opens when the
parent directory is writable, creates `-wal` and `-shm`, rejects SQL writes, and
leaves main database bytes identical. With the parent made unwritable, it returns
`unreadable_library`. This matches [SQLite's read-only WAL contract](https://www.sqlite.org/wal.html#read_only_databases).
The statement at `Registry.swift:335` and the expected unconditional refusal in
`CatalogTests.swift:157` are false premises. The connection itself is not shown to
violate its read-only SQL contract. Missing uncheckpointed WAL data is a different
case; successful opening cannot prove no committed changes were lost.

## Every failing test

Classification: **P** = expected platform mismatch in the available evidence;
**H** = harness/fixture dependency; **D** = confirmed contract/test assumption defect.
An explained failure is not a passing test. The `M` references below identify the
required Mac checks, none of which ran here.

| ID / exact test | Issues | Class / explanation | Mac |
|---|---:|---|---|
| N01 `aVideoSeriesWhoseReplyNamesOnlyAFolder` | 2 | **P** — 308 observation-kind and 304 member-observation assertions require `appeared`; nil birth yields `changed`. Count checks report no failure. | M1 |
| N02 `aReportWithMarkdownPDFAndCharts` | 1 | **P** — Report-kind conjunction fails: fixture birth cannot establish `appeared`; existing stylesheet remains `changed`. Log does not separately print count. | M1 |
| N03 `aDataAnalysisWithCSVFiguresAndANotebook` | 2 | **P** — Notebook and clean CSV both actually report `changed`, instead of expected `appeared`. | M1 |
| N04 `aBuiltAppIsObservedAsOneEntry` | 1 | **P** — App is found as one opaque package; its expected `appeared`/birth-date assertion fails. Package identity/count checks report no failure. | M1+M4 |
| N05 `aLaterSessionEditingAFileAddsItsOwnObservation` | 1 | **P** — Two session observations remain ordered and preserved, but kinds are `[changed, changed]`, not `[changed, appeared]`. | M1 |
| N06 `aHandedOverFileKeepsItsDeliveryWithItsObservationBeside` | 1 | **P** — The delivered work retains its observation; only expected `appeared` differs from actual `changed`. | M1 |
| N07 `theSyntheticHomesCapturePhase` | 2 | **P** — Video and outline observation kinds are `changed`; fixture coverage/path assertions report no failure. | M1 |
| N08 `aMediaPipelineHandsOverItsSegmentsButNeverItsHiddenFiles` | 1 | **P** — 302 members and structural exclusions report no failure; video observation is `changed`. | M1 |
| N09 `keepingMakesAWorkWhoseOneRevisionIsTheFileAsObserved` | 1 | **P** — User keep retains actual `changed` evidence. Keep/undo and identity assertions report no failure. | M1 |
| N10 `aFolderDeliveredTwiceListsItsFilesAtEachDelivery` | 2 | **H** — Future birth-date fixture is ineffective: physically existing appendix qualifies at both future replies under ctime fallback. | M1 |
| N11 `membershipByTimeOnALiveRead` | 3 | **H** — Three move/link/copy preconditions read Foundation ctime as creation. Actual member-selection assertions report no failure. | M1 |
| N12 `aRewriteInPlaceThatPutsTheDatesBackIsNotAsShown` | 1 | **H** — Nil birth aborts the test before approval checks. Additional actual-indexer probe rejects the stale approval without writing a review. | M1 |
| N13 `aFileNamedInAnotherSpellingIsObservedUnderItsDeliveredName` | 2 | **H** — `Report.md` is a missing named target; `report.md` is a different observed path. Identity reconciliation must not fold case blindly. | M2 |
| N14 `aFolderIsSkippedHoweverItIsSpelled` | 1 | **H** — Uppercase home does not exist. Real symlink exclusion works; the asserted case alias depends on volume format. | M2 |
| N15 `aFolderUnderPrivateIsOneProjectWithWhatItsAgentDelivered` | 1 | **H** — Required `/private` temporary-path prefix is absent; project assertions never run. | M3 |
| N16 `aFolderUnderPrivateVarIsOneProjectWithItsFilesThereOrGone` | 1 | **H** — Fixture creation fails at nonexistent `/private` with EACCES; project assertions never run. Running as root would hide the setup issue. | M3 |
| N17 `theHomeFolderAndSystemFoldersAreNotWalked` | 1 | **H** — Only `/Users` fails the exclusion loop: no such path and no home ancestry here. Existing relocated-home scenario remains unvalidated. | M3 |
| N18 `aLibraryThatCantBeOpenedToReadSaysToOpenGleaner` | 1 | **D** — Checkpointed WAL without sidecars is readable if sidecars can be created. Test/documentation assume unconditional refusal contrary to measured dependency behavior. | M5 |

## Separate algorithm assumptions exposed by the probes

These are material limits, not additional explanations substituted for the assertions:

1. **Opaque-package metadata can miss nested edits.** Both real-core probes rewrite
   `Demo.app/Contents/Info.plist`; the observed package-root metadata remains equal.
   `Workspace.walk` deliberately treats the package as one metadata entry. A later
   nested edit can therefore be absent from temporal observations. Native UTType
   recognition is still untested; native root-date behavior needs M4.
2. **`/private` normalization assumes macOS aliases.** `Paths.standard` maps
   `/private/tmp/synthetic-probe-file` to `/tmp/synthetic-probe-file` even though
   `/private/tmp` and `/tmp` do not resolve equally here. This is unsafe as a general
   Linux identity rule. No real conflicting `/private` files were created; the
   collision consequence remains unexecuted. The compatibility experiment must not
   imply arbitrary Linux path correctness.
3. **Home-root safety assumes usual home layout.** `/Users` is excluded through home
   ancestry, not an explicit root policy. Authorizing discovery only inside allowed
   roots must remain independent of that heuristic, especially for relocated homes.
   The absent `/Users` in this run proves no unauthorized traversal occurred; it
   cannot validate an existing other-user-root scenario.

## Reproduce the cloud diagnosis

The retained container and compiled baseline/candidate are prerequisites. Each
command links a diagnostic only; it does not mutate the package or suppress tests.

```sh
python3 eval/retrieval/cycle2/native/run.py --repository /workspace/gleaner-baseline --output docs/retrieval-core/cycle2/native-probe-baseline.json
python3 eval/retrieval/cycle2/native/run.py --repository /workspace/gleaner-cloud --output docs/retrieval-core/cycle2/native-probe-candidate.json
```

## Exact Mac validation handoff

Run in an authorized checkout, as the ordinary user, with only the synthetic
fixture/probe data. Record toolchain, filesystem behavior and SQLite version:

```sh
sw_vers
xcrun swift --version
sqlite3 --version
swift test --filter 'ObservationTests|BundleTests|KeepTests|ReviewTests|ProjectTests|CatalogTests'
python3 eval/retrieval/cycle2/native/run.py --local --repository "$PWD" --output /tmp/gleaner-mac-native-probe.json
```

The `--local` runner path is provided but **has not run on a Mac**. It links the
already compiled debug core, using the native frameworks' normal autolinking. A
local toolchain/link failure must be reported as such, not counted as a test result.
The filtered suite intentionally retains the original failures and assertions.

- **M1 — dates, membership, review.** On a filesystem that supports setting birth
  dates, compare requested and returned dates first. Expected: new observation
  `appeared`, first/second appendix membership false/true, old creation dates
  survive the live move/link/copy fixture, and stale review is refused. A supported
  volume without creation dates should preserve unknown; do not force a fake birth
  date to satisfy the test. Record native clock granularity. A failure after valid
  metadata setup is a core issue to investigate, not an automatic platform excuse.
- **M2 — case and aliases.** Run the probe in its default native temporary location,
  then, if an already authorized disposable case-sensitive APFS location exists,
  rerun with `TMPDIR` pointing to it. Do not reformat a drive or create a new volume
  for this check. Expected on a case-insensitive location: alternate case resolves
  to the same identity. Expected on a case-sensitive location: distinct names stay
  distinct; the two original case-assuming tests can still fail. Symlink home and
  home/Library must be excluded in both. Record actual case behavior rather than
  inferring it from macOS.
- **M3 — private aliases, home ancestry and permissions.** Confirm Foundation's
  temporary directory and `realpath` correspond before expecting a `/private`
  prefix. Existing/missing file path normalization must preserve project identity
  through true `/tmp`, `/var` aliases. Do not create `/private` or elevate to root to
  make setup pass. `chmod 000` should still show locator existence while denying
  bytes and readable stat. Review root policy for a relocated home separately;
  no real other-user folder needs to be scanned.
- **M4 — package registry and nested changes.** Native UTType should identify the
  tested `.app` and `.rtfd` packages as one entry; record actual framework behavior
  rather than assuming the Linux table is authoritative. Inspect
  `package_metadata_unchanged_after_nested_file_rewrite`. If true natively, package
  observation cannot establish that nested bytes are unchanged. That limitation
  persists even if the original kind assertion passes.
- **M5 — SQLite/VFS.** Inspect both writable-parent and unwritable-parent probe cases
  after a clean checkpoint and close. On ordinary modern SQLite, expect the first
  to open/recreate sidecars, refuse writes, and preserve main bytes; expect the
  second to refuse without sidecars. If native behavior differs, preserve SQLite
  version, permission state and sidecar listing before deciding whether the
  contract or implementation should change. Do not test by deleting a live WAL.

No Mac result, release readiness, or universal filesystem correctness is claimed.
