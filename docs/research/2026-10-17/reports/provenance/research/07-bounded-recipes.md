# 7. Bounded, read-only reconstruction recipes

These are future experiment recipes, not operations performed on private data in this study. Keep outputs in a separate research workspace. Do not run historical shell, Git checkout/reset, provider restore, network URLs from logs, or arbitrary converters on the user's originals.

## Common intake

1. Define the target question: declaration discovery, bytes at a named version, bytes at a delivery boundary, or a derivative relation. Specify the delivery event and intended logical identity.
2. Acquire only authorized source records and assets. Record origin, retrieval time, provider/schema version, completeness and source permissions. Retain original selectors plus digest-validated copies if policy permits.
3. Decode into message/tool-call/tool-result/checkpoint/commit evidence units. Preserve unknown record variants and explicit gaps in a coverage report; unknown is not empty.
4. Pair calls and results by stable IDs and session/branch scope. Deduplicate replayed/inherited records without erasing genuinely repeated actions. Do not infer pairing solely by adjacent lines or timestamps.
5. Choose a bounded recipe. Produce a derivation manifest listing exact inputs, transformations, rejected alternatives, assumptions and unresolved gaps. Keep reconstructed bytes separate from observed-source bytes.
6. Independently validate digest, length and media type of any recovered representation. Check its historical association separately. Never label a current read “delivered” merely because a candidate hash matches.

## A. Immutable Git bytes

Prerequisites: authorized repository identity, an available commit/tree/blob, object format and intended path/version. Use read-only Git commands; do not invoke filters, external diff, textconv, hooks, checkout or network hydration.

Resolve the exact tree entry at the exact commit, validate its mode/type and object ID, then retrieve raw blob bytes with `git cat-file blob <validated-object-id>`. An implementation should pass an argument array, validate the hash according to repository object format, and parse tree entries with NUL delimiters. Avoid shell interpolation of a log-supplied path. Compute an independent SHA-256 over the returned bytes and compare recorded size/type.

Record `{repository, commit, tree, path, mode, blob_oid, raw_sha256, observed_at}`. A symlink entry is the link text; a gitlink is a submodule commit reference; an LFS pointer is not the large payload. Missing required objects produce `unavailable`, not an automatic fetch. Git read commands can still encounter repository configuration, alternates or partial-clone behavior; a future implementation should use a controlled read-only copy with network disabled and no optional locks.

This yields exact bytes of a Git version. To assert delivery-time bytes, require the delivery to bind that immutable version or independent evidence connecting working-tree bytes at the relevant boundary. Commit dates, branch names, HEAD today and `git log --follow` do not supply that binding by themselves. See [Git cat-file](https://git-scm.com/docs/git-cat-file).

## B. Provider snapshot or externalized asset

Prerequisites: documented provider/version support, an authorized manifest/export, matching session/checkpoint IDs and available payload. Validate the snapshot's mapping and whether it is before or after the action. Read a copy; never restore the user's working tree.

Record snapshot ID, file identity/path at capture, pre/post boundary, coverage exclusions, payload digest/size, and retention status. Treat files absent from a manifest as unknown unless the manifest contract explicitly makes absence meaningful. A pre-edit snapshot can provide a base; it does not prove an operation afterward. A tool-result asset may preserve exact binary bytes while a visible transcript contains only a thumbnail or reference.

Abstain from historical-byte claims if the required snapshot expired, ID-to-file mapping cannot be verified, or the target lies outside capture coverage. Preserve the evidence that a snapshot was referenced and the precise failed resolution outcome. Provider support is documented in [Part 4](04-provider-evidence.md).

## C. Deterministic edit reconstruction

Prerequisites: exact full base; complete relevant edit sequence; paired results; tool version/semantics; encoding/newline behavior; path identity and an explicit writer-coverage assumption. The base may itself be a prior complete Write request, but that makes the reconstruction conditional on its execution, not observed.

Implement a pure byte/text transition interpreter for an allowlisted edit form. For each edit, validate the expected base digest or exact precondition, match count and scope. Apply to an isolated buffer and compute the output digest. Reject ambiguous matches, fuzzy patch offsets, truncated inputs, inconsistent encoding, notebook serializers without defined semantics, missing results and partial failures.

Maintain a chain of `{input_digest, evidence_ids, transition_spec_version, output_digest}`. If another writer could have intervened, describe the result as “bytes implied by this logged edit sequence under no-intervening-writes,” not as the actual delivered file. A checksum in program stdout is corroboration only under a trusted checksum-producing tool contract.

Some edits can reconstruct all output bytes without an initial base—for example, a verified whole-file replacement that overwrites everything. Prove that the operation covers all bytes and metadata relevant to the representation; do not generalize this special case to ordinary patches.

## D. Reverse reconstruction

Start from an exact final representation only when every inverse is unambiguous and retains overwritten/deleted data. An edit replacing every `a` with `b` cannot generally be inverted from output `b`: original `a` and original `b` can collapse. A unified patch may include enough old lines for a local inverse but still needs untouched base bytes and a unique placement. Retain all possible bases when feasible; otherwise report non-invertibility.

## E. Rename / copy / transcode / export corroboration

Endpoint hashes show endpoint byte identity. An explicit successful `rename` receipt with source/destination object generations and a coherent observation boundary supports a move; same-byte endpoints alone support neither move nor copy uniquely.

For export/transcode, obtain exact input/output versions, execution result, tool/version/parameters and asset dependencies. Report evidence of input consumption/output production separately from the domain judgment that both are representations of one logical artifact. A deterministic isolated rerun can corroborate an operation, but it cannot replace missing historical execution evidence.

An export may depend on fonts, stylesheets, codecs, locale, timestamps, remote assets or random seeds. If those inputs are not fixed, preserve the observed output and state that reproducing it is unsupported. Do not silently substitute a new export for missing historical bytes.

## F. Candidate-only reconstruction

When only names, content similarity, timestamps or contextual declarations remain, generate a bounded ranked candidate set with reasons and disconfirming evidence. Retain `no candidate`, `multiple candidates`, and `not evaluated` distinctly. Show the policy and model version that produced each candidate. A human may assert a link, but that action remains an authored correction with rationale; it does not become a machine observation.

Evaluation should prioritize false historical certainty over maximizing recovery rate. Measure exact-byte recovery against hidden synthetic ground truth, false promotions, abstention coverage, candidate recall at a fixed review budget, and calibration where probabilities are claimed. Real-world rates require a separately authorized and labeled corpus; this study makes no recovery-rate estimate.
