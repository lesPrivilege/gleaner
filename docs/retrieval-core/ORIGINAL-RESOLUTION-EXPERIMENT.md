# Current-original resolution experiment

The development-only [OriginalResolutionExperiment](../../Experiments/GleanerRetrieval/OriginalResolution.swift) compares three ways to expose an explicitly selected original. It does not choose the current working artifact, change delivery admission, or alter CLI/MCP defaults. It is linked only by experimental targets.

| Mode | What the answer establishes | Content read |
|---|---|---|
| `path_only` | A syntactically scoped locator, explicitly `unverified_path`; no existence, symlink-boundary or usability promise | None |
| `metadata` | Metadata of an opened regular file at the selected path, after conservative scope checks; bytes remain unknown | None |
| `hash_current` | A digest of bytes read now, if descriptor metadata and reopened path identity remain unchanged | At most the requested limit plus one overflow/EOF sentinel byte |

The caller supplies authorized roots. No authority is inferred from session cwd, project membership, repository identity or source text. Checked modes walk only the selected path with directory descriptors and `O_NOFOLLOW`, reject nonregular files, and reject every symlink, including links inside the allowed root and ancestors of the root. A rejected link is `denied_scope`, not missing. This conservative policy also rejects native macOS `/tmp` and `/var` aliases; native fixtures must use physical path spellings. Whether a production API should support safe internal links is an unresolved design choice.

The response keeps `capturedSha256` and `captureState` separate from `current.observedCurrentSha256` and `observedAt`. Explicit delivery, folder-member delivery and human-kept origins retain their own evidence kinds and native anchors; `listed` remains a capture state. `matchesCapturedBytes` compares with a recorded digest only. It does not turn a backfill capture into delivery-time proof. Unavailable or unverified current hashes stay nil.

No registry or content store is passed to this API. It cannot complete a listed capture, append a review, approve anything, stage a copy, or change a correction. Current reads can cause the operating system to update access times; the experiment makes no application writes to originals or the library.

## Safety and costs being tested

The shared core's public `Locator`/`Comparison` readers accept paths and do not expose a bounded descriptor reader. The experiment therefore isolates that I/O policy in its own target and uses the same CryptoKit/Swift Crypto SHA256 implementation. It adds no search implementation. Hashing uses a 256 KiB buffer and a temporary `Data` copy of up to that size, with a default 64 MiB byte limit. Oversize files are refused before content reads. Concurrent append cannot bypass the limit: at most one additional byte is read to detect overflow.

The reader checks device, inode, size, modification time and inode-change time before and after hashing, then reopens the path without following symlinks. In-place edits, atomic replacement and a parent-directory swap cause the hash to be discarded when detected. Tests inject mutations after a real read chunk, without adding a production callback API.

These checks are not a filesystem snapshot. Coarse filesystem timestamps, unusual storage behavior or privileged mutation can defeat metadata comparisons. A digest describes the bytes read, and later use of the path requires fresh verification. No wall-clock timeout or cancellation guarantee exists for a stalled regular-file read. Missing or moved originals are reported at their recorded location; the experiment does not scan for replacements, inspect Git history or substitute saved copies.

Path-only work is string processing. Checked modes perform work proportional to path depth; hashing additionally costs O(file bytes) up to its bound. These are algorithmic costs, not measured cross-machine latency guarantees. Process resident memory has not been measured.

## Executed evidence and reproduction

On Linux with Swift 6.2.4, the 12 focused [OriginalResolutionTests](../../Tests/GleanerRetrievalExperimentTests/OriginalResolutionTests.swift) passed in 0.025 seconds initially and 0.045 seconds after the native-only correction described below. They cover all three modes, listed/kept/delivered origin, unequal capture/current hashes, backfill provenance, moved/missing originals, scope-prefix collisions, directories/FIFOs, denied permissions, symlinks, in-place mutation with restored mtime, atomic replacement, parent-directory replacement and concurrent append. An actual registry-listed member retains identical capture, review and correction records; complete synthetic fixture file bytes before and after resolution also match.

```sh
docker exec -w /workspace/gleaner-cloud gleaner-swift runuser -u gleaner -- swift test -j 4 --filter OriginalResolutionTests
```

The opt-in [OriginalResolutionMeasurements](../../Tests/GleanerRetrievalExperimentTests/OriginalResolutionMeasurements.swift) passed separately in 0.086 seconds, comparing 4 KiB, 1 MiB and 16 MiB deterministic files across all modes, with five repeated observations per combination and an oversize refusal case. Setup is excluded and cache warmth is uncontrolled. Its [machine-readable result](cycle2/original-cost-results.json) contains mode, file size, elapsed nanoseconds and actual bytes read; no local paths or content. It makes no process-RSS claim.

Median call time on this Linux VM, milliseconds:

| File size | Unverified path | Metadata | Current hash |
|---|---:|---:|---:|
| 4 KiB | 0.0141 | 0.0268 | 0.1319 |
| 1 MiB | 0.0126 | 0.0250 | 0.8083 |
| 16 MiB | 0.0126 | 0.0245 | 11.1572 |

Path and metadata modes read zero content bytes. Successful hash calls read exactly the file size. A separate 16 MiB file with a 1 MiB hash limit was refused before reading content (one sample, 0.1480 ms). These few repeated observations describe this synthetic run, not cold-storage, GUI or cross-machine performance.

```sh
docker exec -e GLEANER_CYCLE2_MEASURE=1 -e GLEANER_CYCLE2_RESULTS_DIR=/workspace/gleaner-cloud/docs/retrieval-core/cycle2 -w /workspace/gleaner-cloud gleaner-swift runuser -u gleaner -- swift test -j 4 --filter OriginalResolutionMeasurements
```

Independent held-out evaluation and native macOS checks are reported separately. Successful current-original resolution alone does not establish wanted-object recall, first-layer precision, fewer expansions, current-working authority or improvement over Finder.

## Source freeze and native-only correction

The first independent held-out run used original-resolution source SHA256 `dc8b7f9a6c1315d52db1df22f4c2aa39f284642ae094e34867a24f54e8c50320`. Independent code inspection then identified that Darwin's signed `dev_t` must be converted by its bit pattern rather than a potentially trapping signed-to-unsigned numeric conversion. That approved correction changes only the Darwin conditional branch; it is not a response to held-out relevance labels.

The revised source SHA256 is `6bcbc9ff449b2b61dc840aaf2d60439d32f3eaa302d43743de0daacd9c772bfc`. The Linux focused tests and cost run above executed against this revision. At that checkpoint the Darwin branch had only source review. The independent reviewer retained the first-run outputs and reran the unchanged held-out cases against the revised source. The later native execution below supersedes that earlier validation status.

## Native execution failure and isolated repair

The actual [macOS CI run for `24811b0`](https://github.com/lesPrivilege/gleaner/actions/runs/39277126786/job/118144332343)
executed 528 tests in 51 suites on macOS 26.6.2 ARM64 and reported 16 issues, all
in `OriginalResolutionTests`. Checked operations returned `deniedScope` before
reading content where tests expected a current hash, metadata, missing or unreadable
state. Mutation callbacks therefore never ran. The retrieved CI log does not print
the concrete fixture paths, so it does not by itself prove which component was
rejected.

Source inspection identifies an incompatible normalization step: the fixture used
Foundation `resolvingSymlinksInPath`, then the resolver used `standardizedFileURL`.
Foundation can shorten a physical `/private/var` or `/private/tmp` spelling back to
a system alias, which the strict descriptor walk then rejects. Apple's
[path-standardization documentation](https://developer.apple.com/documentation/foundation/nsurl/standardizingpath)
documents removal of an initial `/private`; the primary
[Swift Foundation NSURL implementation](https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/NSURL.swift)
also shows system-directory shortening in both resolving and standardizing paths.
This is a source-backed diagnosis consistent with the CI symptoms, pending
successor native execution. A Linux Swift probe retains `/private/tmp` and has a
non-symlink `/tmp`, so it does **not** reproduce that Darwin-specific shortening.

The isolated repair uses lexical component processing in the resolver and POSIX
`realpath` only during fixture setup. It preserves the physical `/private` spelling
without resolving incoming locators or granting permission through a symlink. The
descriptor walk, scope-prefix boundary, permission failures, bounded read and
mutation checks are unchanged. A new regression checks physical spelling, absent
`/private` locators, dot components and a portable synthetic alias: path-only mode
retains the unverified alias, while checked modes reject it with zero bytes read.
The cost fixture now uses the same POSIX physical-root setup.

Separately, review identified that collapsing `link/..` can change a locator's
meaning across a symlink. The prototype now refuses any `..` component in a
locator or candidate authorized root, in all modes, instead of normalizing it away.
An ordinary existing `out/../out/report.md` is refused too; this is a conservative
scope limitation, not a claim that the file is missing. A second regression covers
ordinary and symlink-parent traversal plus an authorized root containing `..`.
Single-dot components and repeated separators still normalize lexically. This
scope tightening is independent of the native alias diagnosis.

The repaired source SHA256 is
`6c6d5770dd00de69b60c81184335c7282537621c5e4114d805528bae9d414b97`.
The focused Linux suite passed **14 tests in 0.023 seconds**, with a 6.48-second
build. Existing cycle-2 cost numbers above are historical and were not remeasured
for this correction. Native success is still pending; no manual workflow rerun was
requested by this worker.

Core `Paths.standard` intentionally normalizes `/private` aliases for durable
library identity. Such a shortened locator can still be refused by this
experimental reader's conservative no-symlink policy, even when its original is
usable through another spelling. This repair does not make that unresolved policy
compatible with every core locator or silently relabel a denied path as missing.

The reviewed repair is committed as `6a39a13e6929bc7ab1ac24700a0af0929ad2bf44`.
Its ordinary push created [run 39280023363](https://github.com/lesPrivilege/gleaner/actions/runs/39280023363),
job `118152324799`, queued at the report checkpoint. The older documentation-only
run `39278093014` completed with the same 16 original-reader issues and does not
contain the repair. Exact receipt
state is recorded in [cycle3 validation](cycle3/validation-results.json).

## Successor native execution

The decoded job log for repair commit `6a39a13e6929bc7ab1ac24700a0af0929ad2bf44`
confirms **541 tests / 55 suites, 535 passed, six skipped, zero failures**; the
OriginalResolutionTests suite passes. Identical-code checkpoint `3ea45fd` also
passes. This supersedes the earlier pending native-test status, within the physical
fixture boundary. Run/job/check metadata still reports queued despite both complete
logs; see [NATIVE-CI-RECEIPT.md](cycle3/NATIVE-CI-RECEIPT.md) for exact evidence.
Shortened core aliases, safe in-root links and bounded content from the same
verified read remain adoption gates. No additional resolver edit followed these
results, and no workflow was manually rerun.
