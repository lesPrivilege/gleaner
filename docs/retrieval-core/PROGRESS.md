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
