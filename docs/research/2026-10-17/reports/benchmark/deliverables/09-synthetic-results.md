# Executed synthetic probe

The local probe passed 10 of 10 fixture contract checks. This is not a 10-task retrieval result: there were zero model trials and zero compared retrieval strategies. It neither implements nor validates the 26-task benchmark corpus.

Reproduce in the isolated research directory with `python synthetic/probe.py --out run-002` (or another unused simple directory name). The script refuses to overwrite an existing run. It uses Python's standard library, fictional local data and no network or model API. It never runs Gleaner or any repository program. The only deletion is its own newly created derived-output directory during the lifecycle check.

The original execution was `python synthetic/probe.py --out run-001`; evidence is [results.json](../synthetic/run-001/results.json), [input manifests](../synthetic/run-001/fixture-manifests.json) and [configuration](../synthetic/run-001/config.json). The [script](../synthetic/probe.py) SHA-256 at execution was `8c4b6cc1625f62da1d54edf72fc66e8eb70aa608d38acdeea16c74802d5f06f4`. Results record the interpreter, timestamp and exact check outcomes.

| Checked invariant | Observed result | Practical limit |
|---|---|---|
| Equal hash, distinct projects | Two records survive with the same payload hash | Does not test a production identity resolver |
| Equal S1 information | Raw ledger/capture and projection contain the same supplied state | No retrieval-efficiency measurement |
| Missing S0 state | Neither representation supplies a decision or historical snapshot | Missing evidence does not imply a negative real-world event |
| Intent versus fact | V2 approval request remains unsupported; write request has no result; proposed 600 differs from captured 700 | A constructed contrast, not external historical verification |
| Hidden outcomes | Opposite hidden approval outcomes share identical visible input hashes | An agent cannot warrant the hidden distinction from these inputs |
| Partial coverage | Two of three declared source units covered; scope remains open | No agent fallback behavior tested |
| Deterministic rebuild | Canonical output identical after input enumeration reversal | Only this small deterministic projection/configuration |
| Source drift | New input identity and payload mismatch after a controlled path replacement | Drift is distinct from nondeterminism |
| Configuration identity | Extractor-version change alters input identity | Does not prove either extractor is semantically correct |
| Lifecycle separation | Annotation/capture inputs unchanged and reachable after deleting/rebuilding derived output | Does not exercise Gleaner's registry, migrations or admission changes |

The fixture includes a capture value 700, current value 900 and an unexecuted requested value 600 to make unsupported history inference visible. These values are artificial and are not observations about user work. The probe has no token counts, benchmark latency estimates, model accuracy or public/private-log generalization result.

Source inspection, protocol design, synthetic invariant checks and future model trials are separate evidence classes. The first three have artifacts here; the fourth remains proposed. See [controls and execution](08-controls-and-execution.md) for the work required before a scored trial.
