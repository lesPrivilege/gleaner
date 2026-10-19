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

The revised source SHA256 is `6bcbc9ff449b2b61dc840aaf2d60439d32f3eaa302d43743de0daacd9c772bfc`. The Linux focused tests and cost run above executed against this revision. The Darwin branch remains source-reviewed only; no native execution is claimed. The independent reviewer retains the first-run outputs and reruns the unchanged held-out cases against the revised source.
