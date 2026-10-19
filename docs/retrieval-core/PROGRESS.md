# Checkpoints and resume notes

2026-10-19: cloned the public repository separately into a cloud workspace. Remote
main is `2648094610facfd1ae1805f52a9de282043c808f`, query branch is
`cdfe6f4e0ba473ba12309b310018734244efc37c`; query branch already merged. Created
delivery branch and repository-local generic author identity. No user data read.

Fresh roles: explorer owns primary-source notes; capture worker owns extraction /
locator fixes; query worker owns Catalog / thin adapters; runtime worker owns Linux
build boundaries; independent reviewer owns held-out fixtures and final review.
Root owns benchmark, goal spec, integration and delivery. No provider log format
changes planned. Held-out details stay withheld until implementation is frozen.

Runtime initially Debian 13 x86_64, Python 3.12.14, Node 24.19.0, Git 2.52.0,
Docker available; no host Swift. Runtime worker is preparing official Swift Linux
container execution. macOS native tests remain a separate handoff.

Resume: read GOAL-SPEC.md, inspect git status and agent-owned files before editing;
run eval/retrieval benchmark once binaries exist; require independent held-out run
and review before final commit/push. Preserve public-only results. Normal existing
macOS CI triggers on push; inspect again immediately before delivery.

## Convergence-first steering and checkpoint

The later user instruction superseded the build-first milestone order. Existing
code is preserved as prototypes; no further feature scope was added. Root wrote
CONVERGENCE.md, explorer mapped public branches and RAG mechanisms, and reviewer
independently reconciled semantics and sealed a distinct held-out set. Private
conversation recall was not attempted.

Implementation checkpoints: `2d6319b` portability, `7cb1983` syntax, `44624ba`
progressive queries. No extractor-version bump: fresh synthetic libraries only.
Development benchmark rerun at exact implementation revision; binary hashes match
the reviewer's earlier provisional run. First enumeration-harness attempt omitted
the required empty positional query; corrected before retained metrics.

Final actual Linux suite: 346 tests, 328 passed, 18 failed/25 issues matching every
baseline failing test. Independent Swift invariants 4/4 each; 12 CLI scenarios
each with no harness errors. Exact results and commands are committed; unsupported
cases and native exclusions remain visible. Large-scale and semantic method arms
were intentionally not started before contract convergence.

Resume from HANDOFF.md and the intent/spec/implementation matrix, not the original
build-first plan. Discuss the unresolved discovery/identity/selection/access
semantics with the parent; retain defect fixes independently from product choices.

## Second convergence cycle

2026-10-19: continued on the same branch; remote main rechecked unchanged at
2648094, old query branch still integrated. Explorer researched bounded methods;
query and capture workers implemented isolated experimental targets; independent
reviewer sealed 19 scenarios before evaluation. No production source/schema or
provider format changes. Public synthetic material only.

The independent set exposes the named-focus counterexample (wanted deck deferred),
keeps state meanings distinct, records the safe-symlink access failure, and isolates
report-heading ID precision from unsupported table/global finding discovery. The
implementation remained frozen against held-out outcomes. A source-inspected
Darwin signed-device conversion defect was repaired separately, then the same
held-out cases reran; native execution is still outstanding.

Root development-harness review strengthened identity/reachability checks and
workload descriptions before final measurement. Initial calibration results are
retained; they are superseded by the final instrumented run, not silently replaced.
Ordinary tests cannot overwrite held-out evidence; timing workloads are opt-in.

All original 18 failures now have exact assertion/probe explanations and Mac checks.
Nine reflect unavailable birth evidence, eight fixture/layout dependencies, one
the false unconditional-WAL-refusal premise. Additional algorithm assumptions are
reported separately. No failures or expectations were removed.

Resume with cycle2/DECISION-NOTE.md and HANDOFF.md. Preserve all prototypes as
experiments. Review the bounded shared-core current-read / scoped report-ID proposal;
do not adopt named focus as a default or count collapsed groups as relevance gains.

## Third-cycle recovery checkpoint

2026-10-19 15:26 UTC: cloud shell and retained `gleaner-swift` container are connected;
HEAD remains the verified second-cycle checkpoint 24811b0, main unchanged. Parent
reported environment disconnect notices, but no duplicate experiment was launched.
Third-cycle protocol and primary-source methods are written; independent labels
for nine tasks across four corpora are sealed (see cycle3 heldout-labels.json).
Workers are implementing isolated selection/correction tests; no cycle3 execution
result is claimed at this checkpoint. Package target wiring is a pending local edit
until the independent harness exists. Rebuild scope must preserve native observations,
not confuse their deletion with rebuilding a disposable search projection.
