# Retrieval core goal

> **Convergence checkpoint, 2026-10-19.** Later user direction supersedes the
> build-first order below: reconcile public intent, decisions, branches and
> implementation before selecting formal build priorities. Existing code is
> preserved as exploratory prototypes, not an accepted architecture. Read
> `docs/retrieval-core/CONVERGENCE.md` first. Private conversation recall is handled
> by the parent separately; this checkout does not infer it from local logs.

## Baseline and boundary

Fetched 2026-10-19 in an independent Linux cloud checkout. `origin/main` is
`2648094610facfd1ae1805f52a9de282043c808f`; `origin/feat/query-core` is
`cdfe6f4e0ba473ba12309b310018734244efc37c`. Main already includes that branch,
CLI/MCP/headless indexing and shared contextual search. The earlier audit revision
`3bcb6d76ec87f7e94149f4a7fbb32d23fcf0db8e` is an ancestor, not the comparison baseline.
The old frozen-index count is not current algorithm recall. No private corpus is used.

Goal: find useful logical work, choose the intended scope/version, inspect evidence,
and obtain verifiable bytes with little filtering. Exhaustive file discovery is a
separate measure from actionable first results. Finder/agent-library superiority is
an open evaluation question, not a claim this synthetic benchmark can establish.

Read contracts: `AGENTS.md`, `docs/SPEC.md`, review rulings, evidence/lifecycle,
projects/works, query-core, MCP and headless-indexing decisions, and existing core,
command and evaluation tests. Delivery remains explicit reply evidence or a human
keep; temporal observation is neither authorship nor acceptance. Original sources
are read-only. Corrections, reviews and snapshots remain separately governed.

## Scope and architecture

Keep the existing pipeline: provider records → normalized sessions/turns/replies →
safe locator/capture → Registry → Artifact/Work/Organization → Catalog → UI/CLI/MCP.
No alternate retrieval engine for evaluation. Preserve native provider/session,
request/reply location, observation, capture provenance and original anchors.
Do not merge equal hashes or infer approval, publication, or a later ruling.

Bounded prototype hypotheses (not yet selected production priorities):

1. Bounded deterministic locator/extraction repairs for explicit folder and numeric
   shorthand; unresolved patterns must not become fictitious literal deliveries.
   No shell expansion or inferred broad filesystem scans.
2. Measure and improve task selection through existing shared core. Preserve
   project/worktree distinctions, human joins and durable corrections.
3. Progressive read-only project discovery and hash-pinned document sections where
   useful; section IDs are scoped by report/version/position, never global `R1`.
   Keep thin CLI/MCP adapters, bounded pages and explicit index scope.
4. Execute the actual shared core on Linux with narrow platform boundaries. Preserve
   native macOS behavior; native UI, FSEvents and filesystem semantics need Mac checks.

Alternatives: existing contextual lexical rules first (transparent, no new runtime);
FTS projection only if scale justifies migration/synchronization cost; semantic
models only after demonstrated lexical ambiguity. No paid APIs, credentials,
uploads, mandatory model, generic workflow engine or speculative evidence schema.
Deferred: globally indexed message-only findings, inferred cross-report rulings,
automatic identity merges and UI/product/visual choices (owner review).

## Benchmark and acceptance

Use fully synthetic workspaces/logs with declared task labels and ambiguities:
software reviews/specs, episodic media, research and design; mixed intermediates
and outputs, missing/moved files, revisions, same bytes in different contexts,
nested/external worktrees, patterns/ranges, repeated section IDs, partial/stale
indexes and concurrent/aborted work. Author held-out cases independently before
tuning. Metamorphic checks vary names, paths, event order and irrelevant evidence.

Compare current main's **actual shared core**, with only identical Linux portability
shims if necessary, against the delivery branch. Record each separately:

| Measure | Meaning |
|---|---|
| Capture coverage | Explicitly intended delivered files present in the index |
| Task recall | Wanted logical objects returned in declared scope |
| First-page precision | Relevant objects / returned first-page objects |
| Duplicate burden | Repeated logical answers, separately from equal-byte files |
| Attribution | Correct project, object and selected version |
| Originals | Existing exact originals vs saved copies vs unavailable |
| Task success / effort | Correct usable evidence and number of expansions |
| Cost | Index/query wall time, process peak RSS, documented corpus size |

Acceptance: reproducible failing baseline cases; improve targeted failures without
silently broadening evidence; existing portable regression suite and independent
held-out checks pass or every failure is classified. CLI/MCP/core parity must be
executed. No false global absence from partial index, no substitution of current
bytes for selected history, no loss of corrections on reindex. Report regressions
and unsupported cases, not just aggregate scores. No synthetic result closes the
existing native release gates.

## Milestones and delivery

A. Verified baseline, intent/spec/implementation matrix, supersession and branch map.
B. First substantive convergence report to the parent; identify questions needing
   experiments versus design rulings and preserve unconsumed prior work.
C. Bounded baseline/prototype experiments and independently authored held-out tests;
   measure selection separately from discovery before accepting architecture.
D. Reconcile the next research directions and owner rulings, then prioritize formal
   implementation, regression, protocol/parity and scale validation.
E. Reviewable checkpoints with `HANDOFF.md`, exact revisions, source index, evidence
   and resume instructions on `cloud/gleaner-retrieval-core-20261019`; no release claim.

No main merge, releases/tags, credentials, workflow enablement or changes to the
unrelated mounted repository. Existing CI runs `swift test` on macOS for every push
and PR; a branch push triggers that normal test job. Author and committer are
repository-local `GPT Task <gpt-task@example.invalid>`. Process/resume notes live in
`docs/retrieval-core/PROGRESS.md`, separate from this specification.
