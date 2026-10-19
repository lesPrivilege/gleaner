# Bounded implementation proposal after convergence

This is a proposed next build, not an adopted default or a release claim. Preserve
the existing shared candidate search and human Work identity. The experiments do
not justify another first-layer policy merely to choose a winner. Discovery scope,
representation selection and clarification policy remain explicit Opus choices in
the [ledger](CONVERGENCE-LEDGER.md).

## First slice: explicit access to a selected current original

Implement one shared-core/Catalog operation for a caller who has already selected
an existing object or representation and explicitly asks for its current original.
Keep existing exact-historical `read` unchanged. Reuse the existing identifiers and
source scopes; do not introduce a second index, automatic merge, reset or capture
completion. CLI/MCP should only translate the same bounded request and response.

The response must keep the selected historical capture and provenance separate
from an observation of current disk bytes. Explicit path, metadata and bounded
content/hash modes have different guarantees. If bytes are requested, return them
from the same checked descriptor read whose hash and observation time are reported;
the present experiment only returns metadata/hash and is not that implementation.
Opening a returned path later needs a new check. Missing, scope-denied, unreadable,
changed-during-read and limit-exceeded remain distinguishable without changing a
stored capture, review or acceptance fact.

Specify whether each hash covers the whole observed file or the returned span;
bound input I/O independently from returned payload. Trusted roots must originate
in application/caller authorization, never a log cwd or embedded tool text.

Before adopting the experiment, resolve native root aliases at an explicit trusted
root boundary. Preserve the written locator and pin the authorized physical root;
verify traversal relative to that root with descriptor identity checks. Do not
blindly remove `/private`, resolve arbitrary source text, follow untrusted links or
search outside the supplied scope. The current experiment's blanket symlink refusal
still rejects common core-produced `/var` aliases; passing its physical-path tests
does not make that a suitable production availability rule. An implementation must
prove a root-alias policy with native tests before exposing it. Safe internal
symlink support can remain an explicit limitation if the response states it.

## Independent second slice: exact IDs inside one chosen report

Use the already selected report/version as the context. Add exact leading-ID
navigation that distinguishes `R1` from `R10`, preserves repeated matching headings
as ambiguous, and returns version-bound source ranges. Parse once per request and
bound bytes, heading count, response size and continuation state. Keep the same
answers across core, CLI and MCP. A section view is not a durable global finding
identity, and a matching word does not establish a ruling or cross-report relation.
Table/prose occurrences need their own explicitly labeled navigation semantics;
they should not silently become findings.

These slices can be reviewed independently. Their order is a task-priority decision;
neither requires a new first-layer default, inferred working-version authority,
schema expansion or a model. Do not fold the earlier extraction/range prototype
into either slice. Adopting extraction changes separately requires versioned
rederivation and durable-state preservation review.

## Exit criteria and exclusions

- Execute identical core/CLI/MCP requests against synthetic libraries, checking
  bounded output, exact bytes, provenance, scoped errors and no registry/review
  mutation. Retain partial-index health independently from a negative answer.
- Test native aliases, roots and permission failures, concurrent replacement and
  in-place mutation, changed/missing originals, repeated report IDs and changed
  report versions. Keep the independent held-out labels frozen; add newly exposed
  failure classes separately rather than retuning those labels.
- Preserve the baseline comparison: the known 18 Linux failures remain recorded;
  native receipts name their exact revision and compiler/image evidence. Run the
  extra M1–M5 probe and justified native integration checks under the isolation in
  [NATIVE-HANDOFF](NATIVE-HANDOFF.md), without touching a personal library.
- Obtain independent semantics, compatibility and data-safety review before any
  product adoption. Payload and parse limits must be real bounds, not merely a
  selected-row count over an unbounded response.

This proposal does not claim Finder superiority, complete provider-event capture,
global message/finding discovery, stable identity across arbitrary moves, full
database rebuildability, a default review queue or release readiness. Main merges,
signing, notarization, updater credentials and release actions remain excluded.

[ENGINEERING-GATES.md](ENGINEERING-GATES.md) supplies concrete discovery,
approved-rendition, bounded-continuation and migration examples. Those obligations
remain mandatory whichever product default Opus selects.
