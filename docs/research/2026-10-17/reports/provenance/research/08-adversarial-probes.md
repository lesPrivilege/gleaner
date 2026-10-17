# 8. Synthetic adversarial scenarios and probes

The executed probes are independent research fixtures, not Gleaner tests and not samples from private logs. The runner is [run_probes.py](../probes/run_probes.py); detailed witnesses and hashes are in [results.json](../probes/results.json).

## Executed result

**20 checks passed; zero failed.** This includes 12 pairs of finite modeled histories with identical visible evidence but different delivery-time ground truth; three bounded transformation/inverse examples; three concrete isolated filesystem/Git experiments; and two illustrative governance invariants. These are logical/capability demonstrations, not empirical recovery accuracy or enterprise enforcement tests.

| Probe | Visible evidence or constraint | Witness / expected inference |
|---|---|---|
| Write intent without result | Same Write input | One history writes, one does not; requested bytes cannot prove execution |
| Failed write can be partial | Same input and error | Old bytes and partial bytes are both possible without failure-atomicity evidence |
| Success report requires trust | Same success record | A faithful writer and an unfaithful report yield different files; the trust assumption matters |
| Outside writer after success | Same complete Write/success trace | An unlogged later write changes delivery bytes |
| Patch without base | Same replacement and success | Different untouched suffixes survive in two possible outputs |
| Truncated output | Same visible read prefix | Unseen suffixes differ |
| Same bytes, different object | Same full read | Independent logical object IDs remain possible |
| Rename vs copy/delete | Same endpoint read and delivery | End-state bytes do not identify the operation or logical continuity |
| Pre-edit checkpoint | Same captured pre-state and intent | Pending action may or may not have happened |
| Observation vs delivery | Same full earlier read | An unobserved intervening write changes the delivered target |
| Equal timestamps | Same timestamped dispatch record | Different execution orders yield different final states |
| Background completion gap | Same running status | Work completes before or after delivery |
| Known base + exact edit | Full base, exact replacement semantics | Deterministic output digest under stated closure assumptions |
| Complete logged binary payload | Valid complete Base64 | Exact binary recovery; delivery association remains unproved |
| Lossy inverse | Replace `a` with `b` | Output `b` has two possible bases |
| Preserved mtime and size | Actual local rewrite + `utime` | Same mtime/size with different bytes; ctime was not claimed equal |
| Log line insertion | Actual local JSONL rewrite | Former line 2 points elsewhere; record digest still locates original at line 3 |
| Git binary blob | Actual isolated `hash-object`/`cat-file` | Exact binary recovery without checkout or commits; no delivery binding |
| Approval by digest | Two different version digests | Approval target does not automatically follow a mutable path; model illustration only |
| Permission denied | Retained prior-observation metadata | Denied and deleted remain different states; no ACL enforcement was exercised |

The finite model treats tool receipts as visible records and hidden writes as possible world transitions. The lying-success probe deliberately relaxes receipt trust; the outside-writer probe shows ambiguity even when the write itself really succeeds. These should not be conflated. The fixed-base positive probe assumes a closed transition set, whereas the indistinguishability cases intentionally remove that assumption.

## Proposed integration probes, not executed

| Scenario | Fixture construction | Required behavior |
|---|---|---|
| Call/result mismatch | Reuse call IDs in two sessions; deliver results out of order | Pair only in correct provider/session/branch scope; unresolved result stays unresolved |
| Retry and idempotency | Failed partial write followed by retry; same payload repeated | Preserve each attempt, its outcome and final observation; no duplicate delivery inference |
| Truncation without marker | Tool wrapper drops middle bytes but emits apparent success | Require completeness/length contract; fail closed on unverifiable output |
| Notebook/text normalization | CRLF, BOM, non-UTF-8, Unicode combining characters, rewritten JSON notebook | Track raw vs normalized representations; no digest/offset conflation |
| Symlink/hardlink replacement | Same path retargeted between intent, write, read and delivery | Scope identity to actual resolved object at each boundary; detect ambiguity |
| Dynamic shell | Variables, substitutions, globs, pipelines, cwd changes, sourced scripts | Unsupported unless required semantics and inputs are fully bounded; never execute the recorded command |
| Directory bundle | HTML with remote CSS and image changed after page capture | Report captured main file and missing dependency versions; no complete-bundle label |
| Export/transcode chain | Markdown → PDF → image, plus independently generated matching output | Bind each edge to concrete input/output versions and execution evidence; similarity alone remains a hypothesis |
| Partial clone/LFS/submodule | Tree points to unavailable object or pointer payload | Record exact missing object boundary; no silent network hydration or substitution |
| Log fork/compaction/rotation | Parent evidence copied into child, lines shifted, compressed or superseded source | Preserve evidence identity, parentage and generation; reprocessing is idempotent; no false new delivery |
| Parser evolution | Former accepted path becomes excluded; unknown provider record arrives | Supersede extraction assertions; preserve authored corrections and prior observations according to policy |
| Identity correction conflict | Two reviewers concurrently link/split same artifacts | Detect conflict using decision revisions; retain both reasons; do not last-write-win silently |
| Permission revocation | User loses source access after indexing | Deny content and restricted metadata, snippets, counts and cached previews according to policy |
| Cross-source dependency | Public artifact depends on restricted source | Do not leak restricted source title/path/digest/edge through explanations; mark only permitted incompleteness |
| Stale credential/partial scan | Ingestor sees fewer entities due to access failure | No deletion inference; record scan scope/error and preserve historical evidence |
| Approval after replacement | Approved digest at path is replaced; source later deleted | Approval stays version/purpose-scoped; separately resolve retention and disclosure rights |

## An end-to-end adversarial chain

Create `draft.md` from a complete logged payload. Apply an edit whose base is known. Request PDF export but fail after creating a partial PDF. Retry successfully in a background process. Before final reply, an external writer replaces the PDF. Rename a copy and preserve the original mtime. The final reply names both PDF paths; a later Git commit stores only the renamed copy. Delete the transcript asset; revoke access to the original source.

Ground truth should include every write, operation identity, exact bytes at each boundary, the final reply, and permission timeline, kept in a hidden oracle file inaccessible to the reconstructor. Expose progressively richer evidence bundles: declarations only; calls/results; base plus edits; snapshots; exact Git objects; trusted delivery manifest. The expected result is increasing justified knowledge, not universal recovery. Adding a reliable contradiction must downgrade or split claims rather than be averaged away.

## Evaluation measures

Measure separately: exact representation recovery; correct delivery binding; derivative-edge precision; false identity merges; candidate recall under a review budget; calibrated abstention; evidence-address stability across rewrites; correction survival after reindexing; and unauthorized metadata disclosure. Count unresolved cases explicitly. Do not score a plausible candidate as success simply because a reviewer finds it useful.

Use trusted-ground-truth synthetic chains first, then a separately authorized consented corpus. Deliberately include cases with no correct candidate, multiple equally consistent histories, and surviving binary objects with unrecoverable text peers. No claim about real-user performance is supported by this study's 20 checks.
