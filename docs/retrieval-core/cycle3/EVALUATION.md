# Cycle 3 independent evaluation

Labels were sealed at **2026-10-19 15:26:00 UTC**, before implementation inspection,
with SHA256 `c8848fcd422cf114e20211daa5cf95797075714b79636ad2c60fcec5377b9d38`.
The independent set contains eight tasks across four synthetic domains: community
planning, theatre wardrobe, an archaeological atlas, and curated textile records.
No policy output has been used to revise the labels.

The tasks distinguish an admissible set under ambiguous intent from an explicit
required set. Three representations that a person joined remain one Work, while
representation coverage is measured separately. Review filters must not silently
turn a later unreviewed rendition into an approved one. A complete reread of every
fixture log tests human corrections, project names, delivery identities and capture
provenance before selection. This is not a public full-reset operation or the
separate test-only derived-table reconstruction exercise.

## Frozen comparison boundaries

Every policy receives the same base query, page size and optional declared task
constraints. The original unconditioned `Organization.search` call is retained as
a separate comparator: the experimental baseline with status/additional-term
constraints is not mislabeled as current-main functionality.
The relevance label's prose intent is not silently supplied as a model hint:
only its explicit `scope` fields enter the API. An empty scope remains empty even
when the evaluator knows what the human ultimately wants. Clarified task rows
record the additional caller-supplied terms/state and their scripted extra turn.

The known-basename comparator executes actual shared-core queries and opens each
top result through Catalog. It assumes the user already knows discriminative
basenames, which is stronger prior knowledge than a broad project query. The
known-directory comparator actually lists only supplied immediate authorized
folders and reads bounded originals. It assumes the folder is known. Its choice
among listed names is assisted by the labels, as is the policy navigation trace.
These are known-location capability checks and ideal navigation lower bounds, not
blinded operator measurements or the full equal-information protocol in METHODS.
No claim about Finder or human search effort follows from them.

Scripted navigation records actual verified reads, remainder expansions, additional
representation choices and departures from declared task constraints. Choice steps
are lower bounds with known relevance, not measured usability. In particular,
recovering a needed approved rendition from the unmatched remainder is recoverable
evidence but is not successful approved-state selection.

## Executed result

The first actual held-out execution passed its safety assertions at **15:34:13 UTC**
on Linux, Swift 6.2.4, in **0.312 seconds**. It produced **24 policy observations,
24 comparator observations and one all-log reread invariant**. This is one
metric-producing test, not 49 independent unit tests. An earlier build attempt
stopped in another test target before any held-out case executed. Pre-execution
harness corrections and exact hashes are retained in
[heldout-hashes.json](../../../eval/retrieval/cycle3/heldout-hashes.json).

Policy SHA256 stayed
`39219f9736509b9b70fe40cefa97e7a7661cf4c4c49eac8a10de342054879bb7`;
the executed harness SHA256 is
`70b7a74430d0c2bd5eba884579b4884987a69f022c2a2ae8be4506bf29c1bf89`.
No policy or label changed in response to evaluation. Read the
[raw responses/results](../../../eval/retrieval/cycle3/heldout-results.json),
[sealed labels](../../../eval/retrieval/cycle3/heldout-labels.json), and
[harness](../../../eval/retrieval/cycle3/Tests/HeldOut.swift).

An export-only hygiene correction subsequently redacted synthetic runtime roots in
dictionary keys as well as values (`unmatchedReasons` uses Work paths as keys).
The revised harness hash is
`722e0d2e25e74e668cd9b25be2983fdcf6a974ce6a5634920b4e4dc4e608392e`.
Its verification run passed at **15:39:08 UTC** in **0.370 seconds**; every derived
metric equals the first run. The retained result file is this final export, and
[first-run metrics](../../../eval/retrieval/cycle3/heldout-first-run-metrics.json)
preserve the original scored outcomes. No source-selection behavior changed.

| Task | Unconditioned shared core | Common task constraints, baseline and diversified | Task-conditioned behavior |
|---|---|---|---|
| Ambiguous orchard overview | 3/3 selected representations are admissible; all three plausible needs covered | Same | Requests scope; no selected work |
| Clarified site mapping | 1/3 selected is wanted | Additional term selects 1/1 wanted | Same 1/1; caller supplied one clarification |
| Two rehearsal outputs from one reply | 0/2 wanted | Same 0/2; both wanted objects deferred | Requests scope; no selected work |
| Clarified dress-rehearsal package | 0/2 wanted | Extra terms select both wanted objects, 2/2 | Same 2/2; caller supplied one clarification |
| Joined atlas, no representation chosen | 1/2 selected representations admissible; the wanted Work is present | Same; one of its three admissible representations is directly selected | Requests scope; no selected work |
| Editable atlas source | 0/2 wanted representations | Additional term selects the existing editable source, 1/1 | Same 1/1; caller supplied one clarification |
| Approved field rendition | 0/2 wanted representations | No eligible result: matched later rendition is unreviewed | Same empty result despite explicit approved-state request |
| Human-organized textile work after reread | One correct Work, 1/1 admissible selected representation | Same; two joined representations remain reachable | Requests scope despite one uniquely matching Work |

**Diversification produces the same selected objects as the baseline in all eight
held-out tasks.** This set provides neither a gain nor a regression for that
heuristic. Context diversity does not repair the rehearsal task's missing first
layer. Three clarified term queries help every policy identically; that is useful
shared-core query refinement, not a task-conditioned ranking gain.

The task-conditioned arm asks for additional scope in **4/8** tasks. For ambiguous
requests this avoids assuming a single intent, but the orchard baseline already
shows all three admissible outcomes. Its neutral response therefore trades away
immediate objects rather than demonstrating better intent coverage. The uniquely
matching corrected project query exposes unnecessary questioning as well. No user
acceptance or human clarification time was measured.

The approved-rendition case separates identity from selection. A person joined
the editable source, approved field copy and later text rendition. Raw discovery
retains that one Work and all three representations. The approved constraint checks
the query's matched text rendition and excludes the Work; it does not locate the
already reviewed field-copy bytes. All arms can recover those bytes from the
unmatched Work and choose its other representation, but that requires leaving the
declared task result. Do not report this as successful approved-state retrieval.

All **24** policy responses preserve a disjoint selected/deferred/unmatched
partition of the raw Work IDs, and raw wanted-Work and representation reachability
are **100%**. Label-assisted navigation obtains exact wanted bytes in all 24 rows.
This recovery result does not erase first-layer misses or the approved-state
selection failure. No implicit join, duplicate Work or acceptance claim was found.

## Access bounds, operations and preservation

The known-basename arm obtains desired bytes in **8/8** tasks using **15 shared
queries and 15 actual Catalog reads**. The known-directory arm obtains them in
**8/8**, using **eight immediate directory listings and 15 bounded file reads**.
Every target is in the supplied folder; no unknown-location search or recursive
walk is being credited. Directory candidate precision varies with the task: a
folder of three alternatives is only 1/3 relevant when one representation is
wanted. These arms prove access under their declared prior knowledge, not approval
authority: their successful field-copy open does not itself verify its review mark.

Across eight task rows, each policy's recovery trace performs **15 exact Catalog
reads**. Baseline and diversification need one remainder expansion, one expansion
outside the task constraint, and four representation choices. Task-conditioned
needs four remainder expansions, one outside-constraint expansion and the same
four representation choices. These are scripted lower bounds, not observed UI
steps. Each policy executes 11 shared searches: eight base queries plus three
explicit additional-term queries. Clarification turns are reported separately.

The correction case forces every fixture log through a complete actual reread:
**3/3 logs read**. Correction rows, renamed project identity/name, human joins,
not-same-work decision, review records, delivery IDs, capture hashes and provenance
remain unchanged. Selection still finds the human-organized Work by its project
name. No derived tables are deleted, and all selection/comparator calls preserve
user state. The separate reconstruction tests cover a different operation and must
not be conflated with this reread.

Small-workload median policy latency was approximately **0.182 ms** baseline,
**0.171 ms** diversified and **0.155 ms** task-conditioned. Single runs at this size
do not support a speed ranking. Serialized policy responses range from **4,407 to
21,538 bytes**, despite first layers of zero to three objects. These are actual
full response sizes before synthetic-path redaction, not bounded public payloads.
No peak RSS, broad-corpus generalization, native filesystem validation or human
effort experiment was performed by this held-out suite.

Normal test runs export nothing; explicit `GLEANER_CYCLE3_RESULTS` is required:

```sh
GLEANER_CYCLE3_RESULTS=/tmp/cycle3-heldout.json \
  swift test -j 4 --filter Cycle3HeldOutTests
```

Cloud reproduction uses the existing container and isolated checkout:

```sh
docker exec -w /workspace/gleaner-cloud gleaner-swift \
  runuser -u gleaner -- env GLEANER_CYCLE3_RESULTS=/tmp/cycle3-heldout.json \
  swift test -j 4 --filter Cycle3HeldOutTests
```

## Independent source review

Cycle3Selection reuses `Organization.search` for both base and additional-term
queries, retains Work IDs, and exposes each already joined file as a representation.
Its context spread is a deterministic ordering heuristic over project and native
reply/unit identities, not evidence of relevance, delivery authority or acceptance.
The original matched delivery remains in `rawDeliveryID` when added terms select
another representation. Explicit `captureProvenance` and `deliveryEvidence`
prevent a listed member or later capture silently becoming an individual handoff.

The optional byte-state constraint evaluates the matched capture through existing
`Review.standing`; it does not search for another approved representation. This
limits the task it can answer. A result outside the constraint remains in
`unmatched` with its reason; that is recoverability rather than successful matching.
No registry or filesystem access is performed by the selector, and no source
content is executed. Its API takes an already scoped Organization; a future adapter
must still apply the library's source and authorization rules before constructing
that Organization.

Two adoption issues are visible without assigning relevance labels. First, the
task-conditioned arm asks for scope whenever the caller supplies no extra scope,
even if the base query is already exact. Clarification is a cost and cannot be
assumed to improve an answer. Second, `limit` bounds selected rows, not the full
response: raw, eligible, deferred and unmatched arrays repeat candidate data,
representations are unpaged, and the neutral overview is unbounded. Diversification
compares up to candidates × selected slots. These remain isolated experiments;
they are not bounded public CLI/MCP contracts, a schema migration, or a replacement
for the core's current identity rules.

## Final independent checkpoint review

The convergence ledger and HANDOFF accurately distinguish measured outcomes,
ideal navigation bounds and unresolved product decisions. No new selection policy
is supported as a universal default. The experimental code remains outside the
app/CLI/MCP dependency paths; no provider adapter or correction schema changed.

The separate original-resolution repair was reviewed at source SHA256
`6c6d5770dd00de69b60c81184335c7282537621c5e4114d805528bae9d414b97`.
It preserves physical `/private` spelling without Foundation path shortening,
keeps descriptor traversal and `O_NOFOLLOW`, and rejects parent (`..`) components
before filesystem access in both locators and authorized roots. The latter is a
conservative behavior restriction, separately identified from the native alias
repair; ordinary parent traversal is denied too. POSIX `realpath` is used only to
construct physical synthetic fixture roots, not to approve arbitrary input links.
This is appropriate for the experimental checkpoint. Core-normalized short aliases
and safe symlink access remain unsupported. The 14 focused Linux tests and source
review do not substitute for a successor native CI receipt.

The correction reconstruction fixture was also inspected. Its safe arm deletes
only log cursors, session/delivery projections and run-status metadata, retaining
captures, native spans/observations, kept evidence, authored rows and namespace.
The negative control intentionally deletes native observations inside its disposable
fixture and demonstrates loss of a kept missing Work. Those observations cannot
be promised rebuildable from current files. Folder membership tables are empty in
these fixtures, and generation restarts in the reconstruction harness; neither
folder-history migration nor concurrent cursor continuity is validated. This is
not a public reset contract.

No additional blocker was found to preserving and testing this isolated checkpoint.
Native acceptance must reference the exact successor commit and executed tests.
The metric suites' safety assertions do not assert every relevance expectation:
a passing native suite without exported measurements is not proof of native
retrieval success. First-layer choices, bounded adapter contracts, current-original
alias support and any production migration still require their stated follow-up.
