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
