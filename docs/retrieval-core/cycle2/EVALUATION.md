# Cycle 2 independent evaluation

2026-10-19. **No tested first-layer policy dominates the others.** Explicit task
state selection and separately labelled current-original observation are feasible
without conflating delivery, review, publication or current bytes. These are
experimental results, not accepted defaults or a completed object model.

## Independence and execution

An independent evaluator authored four state histories, four selection tasks,
seven original-resolution cases and four report-ID cases before inspecting the
policy implementations. Labels were sealed no later than **15:04:31 UTC**:

`d11c155fdcb3a42e7d8e7c20c681e4ccb7f0b93466dfe0ea0ab61f71d645aab9`

The four policy sources were frozen no later than **15:10:44 UTC**; their exact
hashes are in [heldout-policy-hashes.json](../../../eval/retrieval/cycle2/heldout-policy-hashes.json).
No policy was changed in response to held-out results. All material is synthetic;
temporary roots are replaced by `$SYNTHETIC_HOME` in retained results. Review and
publication fixtures use `Indexer.review`, not fabricated database rows.

The first actual Swift 6.2.4 Linux run passed the suite's safety assertions in
**0.552 seconds**, producing **101 policy observations from 19 scenarios**:
60 state selections, 12 first-layer selections, 21 original resolutions, and eight
section lookups. This is one metric-producing test, not 101 independent unit tests.

Afterward, a harness-only change required an explicit `GLEANER_CYCLE2_RESULTS`
export path so ordinary `swift test` and CI cannot overwrite checked-in evidence.
The same cases ran once more in **0.538 seconds**. Every derived metric was equal,
excluding timings and raw responses containing fresh random identities. Labels
and all four policy hashes remained unchanged in that repeat.

Independent code review then found that Darwin's signed 32-bit `dev_t` needs a
bit-pattern conversion to avoid a trap on a valid negative device identifier.
That narrow source correction changed OriginalResolution's hash from
`dc8b7f9a6c1315d52db1df22f4c2aa39f284642ae094e34867a24f54e8c50320` to
`6bcbc9ff449b2b61dc840aaf2d60439d32f3eaa302d43743de0daacd9c772bfc`.
It was not driven by held-out labels and does not change the Linux branch. The
unchanged held-out suite ran again at **15:17:50 UTC**, passing in **0.453 seconds**.
All 101 observations retain identical derived metrics to the first run. The
Darwin branch remains source-reviewed, not executed. The manifest preserves the
original frozen hashes and records the final hashes separately.

The original run and final explicit-export run are retained:

- [First run](../../../eval/retrieval/cycle2/heldout-results-first-run.json), harness hash
  `8d53b66748d132b9522471bc4ebcecffa5a487ceaa405b631fdb027a4300c98d`.
- [Final explicit-export run](../../../eval/retrieval/cycle2/heldout-results.json), harness hash
  `c3601b605be21458b1a921535734d63630af96609961dfde653281b2204dd735`.
- [Sealed labels](../../../eval/retrieval/cycle2/heldout-labels.json) and
  [executable harness](../../../eval/retrieval/cycle2/heldout.swift).

Reproduce from the repository with the same Swift environment:

```sh
GLEANER_CYCLE2_RESULTS=/tmp/cycle2-heldout.json \
  swift test -j 4 --filter Cycle2HeldOutTests
```

In this cloud environment:

```sh
docker exec -w /workspace/gleaner-cloud gleaner-swift \
  runuser -u gleaner -- env GLEANER_CYCLE2_RESULTS=/tmp/cycle2-heldout.json \
  swift test -j 4 --filter Cycle2HeldOutTests
```

The implementation checkpoint is `7e004a7` plus the frozen experimental files.
Policies use real `Organization.search`, `Reviews`, `Review.standing`, and Catalog
outline/read operations. The harness implements no competing retrieval engine.

## State selection

| Policy | Correct selected requested fact | Correct requested fact disclosed | Interpretation |
|---|---:|---:|---|
| Explicit intent | 20/20 | 20/20 | Selects the requested state and preserves unknown/absent states |
| Disclose all states | No automatic selection | 20/20 | Adds an explicit selection step; does not pick a default |
| Newest-delivery control | 4/20 | 20/20 | Deliberately naive negative control; **not current Catalog baseline** |

Cases include approved/published old bytes, a newer delivered draft, still newer
undelivered disk bytes, a latest review requesting changes, publication without
review, and a missing original with retained historical states. “Current working”
remains unknown in every case: no working-state marker exists. Last reviewed
selects a negative verdict when it is the latest verdict; it does not mean last
approved. Publication never manufactures approval.

The 20/20 result establishes conformance to these small, explicit state requests.
It does not choose a useful default for an ambiguous task, establish availability
of every selected historical state, or show an improvement over main's retrieval.
Disclosing all facts and selecting one are different interactions.

## First layer versus reachable evidence

Precision below counts immediately actionable objects, not a collapsed group's
members. A multi-member group is a navigation row and has no object precision
until expanded. Every policy keeps all candidates reachable in these cases.

| Declared task | Shared-core baseline | Named focus | Native reply groups |
|---|---|---|---|
| Open the permit booklet; retain calculations as evidence | 1/5 first objects relevant; wanted object visible | 1/1 relevant; wanted object visible | One group; one extra selection reveals 1 wanted and 5 unwanted members |
| Continue editing the stakeholder presentation | 1/4 relevant; editable deck visible | 0/1 relevant: guide remains, wanted deck moves to deferred matches | One group; one extra selection reveals 1 wanted and 3 unwanted members |
| Reuse the intermediate threshold CSV | 1/3 relevant; CSV visible | 1/1 relevant; CSV visible | One group; one extra selection reveals 1 wanted and 2 unwanted members |
| Retrieve equal-byte forms in two projects | 2/2 relevant, two contexts | 2/2 relevant, two contexts | Two single-member rows, two contexts |

The presentation task deliberately names its ambiguity: the query alone cannot
distinguish the editable deck from its editing guide; the declared task supplies
that relevance label. A filename preference cannot safely decide that ambiguity.
Named focus helps two tasks and hides the wanted object in another. The CSV case
also counters a blanket preference for document/media types over intermediate
data. Reply grouping preserves scope and discovery, but moves direct access behind
selection. It does not establish less filtering after expansion.

All **12 policy/task combinations have 100% reachable wanted-object recall** and
zero repeated work IDs. This is not 100% first-layer recall. It is also not proof
of semantic duplicate detection: equal bytes are deliberately kept separate.
The API currently includes all group members and `allMatches` in its response, so
expansion counts are interaction proxies, **not measured extra API calls or
reduced payload size**. No human or Finder comparison was performed.

## Listed and current originals

Across **21 mode/case observations**, verified hash claims were correct, historical
capture values remained unchanged, and no registry, capture, review or source
writes came from the resolver. The deterministic mutation hook is explicitly a
test writer and is recorded separately.

- Path-only mode returns an unverified locator without reading bytes or claiming
  existence. Its lexical authorization check is not filesystem verification.
- Metadata mode reads no bytes and makes no hash claim. Missing, nonregular and
  denied paths are distinct from metadata observed successfully.
- Hash-current mode meets **6/7** sealed observation expectations: it observes a
  listed member without inventing a historical hash; distinguishes current changed
  bytes from captured bytes; and correctly reports missing originals, scope escape,
  directory replacement and mutation during reading.
- The remaining case is a useful original reached through an **in-root symlink**.
  Checked modes deny it too. This is a truthful conservative refusal with a real
  usability cost, not success or a missing file.

Checks compare the registry files, captures, reviews and source files around each
resolver call. Current observation stays distinct from a historical capture;
`matchesCapturedBytes` remains unset when no captured hash exists. A returned path
and observed hash do **not** pin bytes for a later open: reuse must verify again.

Native fixtures canonicalize the synthetic temporary root and locator spelling
before introducing deliberate symlinks. This avoids incidental `/tmp` or `/var`
aliases in the test setup; it does not prove that ordinary Mac aliases work.
The policy rejects every symlink ancestor. macOS validation must measure that
false-negative cost explicitly rather than silently canonicalizing product input.

## Report-local identifiers

For a report containing both `R1` and `R10`, substring matching returns both
(precision **1/2**); exact leading-identifier matching returns `R1` alone
(precision **1/1**). Repeated `R1` headings within one report remain two distinct
sections, and `R1` in another report retains a different byte-bound identity.
Supplying another report's section ID is refused. Returned section bytes were
read through the exact-version Catalog path.

A finding represented only in a table remains unreachable through both heading
policies. An empty heading result is mechanically correct but **fails the declared
logical-finding task**. Global search returns zero `R1` hits in all four report
cases; report-local lookup must not be reported as global discovery success.
From an already selected report, outline then exact section reading takes two
scripted expansions. No decision or ruling is inferred from either heading text
or duplicate identifiers.

## Independent source review and limits

The provisional original resolver uses descriptor traversal with `O_NOFOLLOW`,
checks descriptor metadata before/after hashing, and reopens the path to check
identity. Its byte bound includes one overflow sentinel. Metadata-only mode is
a point observation; neither it nor hashing guarantees the path remains unchanged
after the call. The API accepts no registry and does not execute source content.
Authorized roots remain an explicit caller responsibility, not inferred from cwd.

State facts now retain capture provenance and distinguish an explicitly named
delivery from a folder member. This matters because `kept == nil` alone does not
establish an individually named handoff. Historical records and present-byte
standing remain separate. No general tool-call/role evidence graph was added.

Section lookup's exact-token policy is intentionally narrow: leading plain-text
letters/numbers/underscore/hyphen. Markdown formatting, table IDs and narrative
references need further design. A source-byte limit is not a complete resource
bound: Catalog constructs all heading IDs before paging, and SectionLookup reads
each outline page by re-verifying/re-parsing the document. Very many short headings
can therefore cause large allocations and repeated work. This is a source-inspected
risk; no large-heading workload was executed in this held-out run.

Measured first-run in-process median latencies were approximately **0.020 ms** for
state evaluation, **0.123 ms** for first-layer policy evaluation and **3.20 ms** for
report lookup plus its harness verification. Hash-current calls read at most
**37 bytes** in these small fixtures; bounded large-file behavior is not inferred
from them. No independent peak-RSS measurement was taken. These are small-workload
observations, not scale or user-effort results.

Native macOS filesystem behavior, UI composition, actual expansion interactions,
large-corpus resource use, broader finding representations and generalization
remain open. The experiments support exposing separate facts and preserving
recoverable alternatives. They do not settle first-layer defaults, a symlink
policy, an evidence taxonomy, or a persistent logical-object architecture.

## Checkpoint review

The independent review checked the final decision note and handoff against these
results. Their bounded current-read/report-ID proposals preserve the distinctions
above. Development's expanded-member precision and this report's immediately
actionable-object precision remain separately defined; neither should replace the
other when comparing grouping.

The experimental target is consumed by tests, not the shipped app/CLI/MCP targets.
This cycle introduces no schema migration or registry mutation API. Prior-cycle
extractor-version and native regression limitations in HANDOFF still apply; this
evaluation does not clear them. Retained result files contain synthetic placeholders,
and ordinary tests require an explicit environment variable before exporting them.

Before adoption, address these source-grounded gaps:

- Preserve authorization by native root identity while supporting safe aliases;
  OriginalResolution's current lexical-root check and all-symlink refusal are an
  explicit conservative experiment, not a finished Mac availability policy.
- Return any current content from the same checked descriptor observation, retaining
  its own time/hash and capture provenance. The current API returns observations,
  so a separate later path read cannot inherit its verification.
- Bound heading count and repeated parsing in SectionLookup and Catalog outline.
  Bound group members and continuation payloads too: FirstLayerPolicies limits
  rows, while `allMatches` and each group's `members` remain unrestricted.
- Keep unknown working intent and historical capture provenance visible at adapter
  boundaries. A `known` last-delivery fact containing a first-seen-later capture
  must not become a claim that the captured bytes existed at delivery time.

These are adoption constraints, not reasons to suppress or retune the held-out
counterexamples. No additional blocker was found to preserving this explicitly
experimental checkpoint for review.
