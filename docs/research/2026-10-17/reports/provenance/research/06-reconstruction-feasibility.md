# 6. Reconstruction feasibility matrix

This matrix is a proposed decision discipline. It separates obtaining bytes from binding those bytes to a historical delivery. Categories D/I/X/O/R/T/H are defined in Part 5.

## The decision rule

Let E be surviving evidence and A explicit assumptions about tools, storage, clocks, completeness and writers. Let H(E,A) be all histories consistent with both. Exact delivery bytes are identifiable only if every history in this set assigns the same bytes to the same delivery-bound representation. If the set is empty, evidence/assumptions conflict. If it permits multiple byte values, report candidates or abstain. Finding one successful reconstruction is not proof of uniqueness.

This is an analytical criterion, not a claim that arbitrary shell programs can be enumerated. A bounded adapter should recognize a deliberately small deterministic subset and reject the remainder.

“Delivery time” must itself be defined: assistant message creation, final-turn completion, file-upload binding, and recipient retrieval are different events. A path mentioned in a message usually names mutable state. An attachment/version ID explicitly bound by the delivery service is stronger temporal evidence than a nearby filesystem read.

## Evidence requirements

| Surviving evidence | Exact bytes obtainable? | What is needed to bind to delivery / prove an edge | Safe outcome without it |
|---|---|---|---|
| Final reply names a missing path | No | A retrievable immutable version or uniquely reconstructible bytes plus delivery binding | D; unavailable artifact remains cataloged |
| Complete Write input, no result | The requested payload may be decoded exactly | Verified tool semantics/encoding, actual completion, path identity, and no unexplained state changes before delivery | I; requested bytes, not observed file bytes |
| Write input plus success result | Conditional post-write R if tool semantics fully specify write and payload is complete | Result bound to call ID; successful completion/atomicity; cwd and symlink target; bytes/encoding; delivery-bound observation or closed transition history | X + conditional R; success is a tool report, not an independent disk observation |
| Write returns error/cancel/timeout | Payload remains available, resulting file may be old, new, empty or partial | Defined failure atomicity or independent post-failure capture at a bound point | I/X failure; unknown final bytes |
| Complete read result | O for the returned representation if faithful and untruncated | Trustworthy read semantics, size/completeness/encoding, atomic read or snapshot, identity and time binding | Observed text/bytes at read time, not automatically full file or delivery |
| Whole-file immutable snapshot/blob | Yes if retrievable and digest/type verified | Manifest or tree mapping object to path/session/version; evidence binding that version to delivery | Exact version bytes, delivery association H until established |
| Exact base + all deterministic successful edits | R at each modeled transition | Exact edit semantics (encoding/newlines, matching and replacement count), preconditions, order, no omitted/interleaved writers, final delivery binding | Conditional reconstruction with assumptions; unexplained gap blocks exact delivery claim |
| Patch/Edit without full base | Usually no; some touched spans are known | Complete base or exhaustive coverage proving every output byte; unique application | Partial known spans or H; never fill missing bytes with model guesses |
| Complete final file + reversible edits | Sometimes earlier R | Every inverse unambiguous; deleted/overwritten bytes retained; no hidden edits; exact order/base | Abstain if inverse loses information or multiple bases fit |
| Git commit + tree + blob | Yes for that committed path/mode | Exact commit/tree/path/blob and repository identity; delivery explicitly names version or independent observation binds it | O of committed version. Commit timestamp alone does not bind working-tree state |
| Git LFS pointer or submodule entry | Pointer/gitlink bytes only | LFS object or submodule repository/object actually available and verified | Representation reference with unavailable payload; never preview pointer as original asset |
| Git rename/copy detection | Endpoint blobs may be exact | Actual move event with identity continuity, or authored relinking with its basis | H relation from similarity; content equality does not choose rename vs copy vs coincidence |
| Shell `echo`, heredoc, `cp`, `mv` text + exit 0 | Only under a strict modeled subset | Expansion/environment/cwd, referenced input versions, quoting/encoding, per-operation effects, completion and no competing writers | X report; command parsing alone cannot resolve dynamic behavior |
| Arbitrary shell/script, pipeline or async command | Generally not from text alone | Full relevant state and execution trace, inputs, versions, effects and completion; sandbox replay only if separately justified | H or unsupported. Never execute recovered commands merely to infer history |
| Transcode/export command + output | Exact output if preserved | Input/output digest binding, trusted execution identity, parameters/tool version and successful generation; required assets accounted for | Output O plus possible derivative edge; file similarity/format names alone insufficient |
| Deterministic rerun yields matching output | Current replay bytes yes | Historical inputs/tool/environment, stable deterministic semantics and historical execution evidence | Reproducibility corroboration; a new run is not the old run |
| Checkpoint before a tool/turn | Exact pre-state if recorded and available | Version-specific coverage/manifest, all later transitions to delivery or a later matching boundary | O of checkpoint; no assumption it is post-write or delivery-time |
| Logged encoded binary / tool asset | Yes if complete, decodable, verifiable | Full asset/reference, decoding specification, digest/length and output-to-call binding | Binary candidate; missing/truncated encoded data is not reconstructible |
| Current file + mtime close to delivery | Current bytes yes | Trusted version-bound evidence or complete relevant history | O now; mtime can be preserved, coarse, reset or unrelated to causal order |
| URL, ETag, title or content hash only | Only if representation retrievable | Origin/version/representation semantics, correct authorization/content negotiation and delivery binding | Pointer or digest evidence, not byte recovery |
| Directory/HTML with dependencies | One entry or main file may be recoverable | Complete manifest of entries/dependencies, symlinks, versions and external resources under defined boundary | Partial representation; no claim of a self-contained historical bundle |

## Cross-cutting failure modes

- **Partial execution:** one shell exit code may summarize many operations; a successful final pipeline command can hide earlier failure. A process still running at delivery leaves later effects open.
- **Outside writers:** editors, formatters, watchers, subagents and background processes can change the same target without appearing in the selected transcript. “No other write in this log” does not establish a closed world.
- **Unfaithful output:** stdout is arbitrary program output. It may echo a predicted hash, print “success” before failing, or omit a truncation marker. A diagnostic is not a filesystem receipt unless the trusted tool contract makes it one.
- **Read races:** opening a path, hashing it, copying it and later resolving that path are different operations. Even one file descriptor can observe in-place concurrent mutation; before/after `stat` equality is not a general atomic-snapshot proof.
- **Identity ambiguity:** paths are reused; inodes may be reused; hardlinks and symlinks create aliases; identical blobs can belong to unrelated logical objects. Repository/worktree IDs, object generations and authored decisions can narrow ambiguity.
- **Order ambiguity:** log order may be append order, dispatch order or replay order. Use call/result IDs, parentage, sequence constraints and explicit completion boundaries. Clock proximity is supporting context only.
- **Evidence gaps:** compaction, retries, forked inherited messages, rotation, retention, dropped events, unsupported schemas and redaction can erase distinctions needed for exact reconstruction.

## Proof boundaries for derivative edges

Separate `declared-derived-from`, `execution-reported-derived-from`, `observed-input/output-binding`, `reproduced-under-assumptions`, and `human-asserted-link`. A transcode can establish a different representation of the same conceptual work under a domain rule; it may instead be a new artifact. A rename typically changes a locator, but a move command acting through a symlink or overwriting a destination can complicate identity. Domain semantics choose logical continuity; bytes and operation evidence constrain that choice.

An exact-output claim should identify whose observation is trusted and what integrity mechanism protects it. This report does not promote ordinary mutable local logs to forensic nonrepudiation. PROV encoding and content hashes organize and check evidence; they do not make its claims true.
