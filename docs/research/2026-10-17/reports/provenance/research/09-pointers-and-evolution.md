# 9. Pointer resolution, staleness, schema evolution and correction

This part proposes boundaries for later experiments. It does not define a new URI standard or require a universal resolver service.

## One resolver interface, multiple truthful outcomes

An interface such as `resolve(locator, principal, requested_representation)` can be useful if it unifies **result semantics** rather than pretending all sources behave alike. Return `{status, source_version, representation, observation, integrity, capabilities, limits}`. The resolver must not automatically broaden permissions or silently replace a requested historical version with current bytes.

| Locator family | Required specificity | Main failure modes |
|---|---|---|
| Local path | Machine/volume/workspace scope; path as supplied; cwd; normalization rules; optional object-generation or bookmark | Rename, reuse, case/Unicode normalization, symlink retargeting, disconnected volume, permission change |
| Git object | Repository identity and object format; immutable commit/tree/blob; path/mode when meaningful | Missing/pruned object, partial clone, alternate object store, LFS pointer, submodule reference; branch name drifting |
| Log evidence | Provider/schema; session/branch; native record ID; source generation; record digest; byte/structured selector | Rotation, compaction, inherited replay, rewritten IDs, externalized payload, truncation, changed encoding |
| URL | Origin and resource identity; version/archive identifier where available; representation and authorization context | Mutable response, redirects, negotiated content, signed-link expiry, account-specific content, unavailable archive |
| Captured representation | Store namespace; digest algorithm/value; size/media type; acquisition manifest | Eviction, corruption, ACL mismatch, missing dependencies, uncertain historical binding |

Recommended statuses: `resolved_exact_version`, `resolved_current`, `ambiguous`, `missing_observed`, `permission_denied`, `source_unreachable`, `expired`, `integrity_mismatch`, `unsupported`, `not_checked`. Distinguish a provider's response from a historical conclusion. A 404 may hide denial; “missing observed at T” is not “never existed.” An enterprise-facing response may have to coarsen these statuses to avoid existence leakage.

Record the requested locator and the actual resolution chain. Redirecting or finding a replacement is a new assertion with evidence. A search hit for a similar name is a candidate, never an automatic exact-version substitute. Prefer explicit capabilities: `can_read_current`, `can_read_version`, `can_select_record`, `can_report_permissions`; unsupported capabilities remain visible.

## Staleness is multidimensional

Store `last_resolution_attempt`, `last_successful_observation`, source event time, capture time, and authorization-check time separately. Current availability, content freshness, identity confidence and permission freshness can age differently. A cached ACL decision and a cached byte snapshot do not share a safe TTL by default.

Content hashes are useful for equality/fixity under their algorithm assumptions. They are not logical object IDs, source locations, authenticity proofs, or availability guarantees. Identical bytes do not merge objects; a changed digest does not necessarily create a new logical object. Hashes of short sensitive values can also reveal information through guessing, so enterprise metadata policy must cover them.

Watchers should schedule checks, not certify complete history. Reconcile after overflow, restart or schema change. A manifest of observed source coverage lets a future user distinguish “no records found in the checked interval” from “all historical records inspected.” A successful read today cannot retroactively close a gap yesterday.

## Source-preserving extraction

Preserve natural boundaries: message, tool call, result, checkpoint entry, Git tree entry, and attachment reference. A long assistant turn can have several records; a short tool result can point to a large external asset. Use selected spans only when their containing record and representation are identified.

Store original schema ID/version and extraction version with normalized assertions. Keep raw evidence locators and, when authorized, minimal immutable record snapshots. Normalization, OCR, redaction, summarization and format conversion each produce a new representation with an explicit mapping or an acknowledged mapping loss. When text extraction cannot preserve exact byte positions, expose that limitation rather than inventing offsets.

Support provenance of the extraction itself: input evidence IDs, rule version, run ID, output assertion IDs, exclusions, errors and coverage. Rebuilding a search index should not erase a prior observation that now lacks its source. Conversely, retaining a pointer does not automatically justify retaining sensitive raw bytes forever.

## Schema matching is not migration

Candidate field correspondences can use names, types, structure, value examples and constraints, as studied by [Rahm and Bernstein](https://dbs.uni-leipzig.de/files/research/publications/2001-1/pdf/VLDBJ-Dec2001.pdf). A mapping still needs a domain decision: is a provider's `completed` field model completion, process exit, durable write, or stream termination? Treating all four as one `success` field loses evidence.

For every schema revision classify changes: additive field, rename preserving meaning, type/units change, semantic change, split/merge, or removal. Use stable field IDs where appropriate, preserve original values and writer schema, and version transformations. [Iceberg](https://iceberg.apache.org/docs/latest/evolution/) and [Avro](https://avro.apache.org/docs/1.12.0/specification/) provide concrete precedents for identity and reader/writer distinctions, not a ready-made provider schema.

Never backfill a newly introduced boolean with `false` when the historical meaning is “unknown.” Never read a default synthesized by a new schema as a source observation. Preserve `missing`, `null`, `redacted`, `unparseable`, `unsupported`, and `false` separately where they affect claims. Keep unknown extension fields available by reference for future re-extraction.

## Correction and review

A correction record should target a stable assertion/representation or identity decision, include author/time/reason, and supersede rather than overwrite the previous decision. Reindexing can regenerate proposals and invalidate stale derived conclusions, but should not silently erase or reinterpret authored corrections.

Use explicit merge/split/alias decisions for logical identity. If stable IDs change during migration, preserve an auditable mapping; unresolved references remain unresolved. Concurrent corrections should use a revision precondition or explicit conflict record. A reviewer rejecting an inferred edge should not destroy the underlying evidence or prevent later reconsideration with new evidence.

Approval should specify representation digest/version, purpose, audience or policy scope, actor authority and revocation/supersession. An approval of one exported PDF does not approve its edited successor, its source file, or every sibling representation. Review can concern content quality while provenance remains uncertain; the UI should not collapse the two.

The proposed candidate/cataloged/versioned/reviewed words can be explored as views over independent facts. They should not become an irreversible workflow until concrete user tasks show what transitions, conflicts and reversals mean.
