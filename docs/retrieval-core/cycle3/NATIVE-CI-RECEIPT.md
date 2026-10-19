# Native test execution receipt

Decoded GitHub job logs confirm that the repaired implementation completed native
`swift test` successfully on macOS 26.6.2 ARM64. **541 tests were enumerated in 55
suites: 535 passed, six opt-in tests skipped, zero failures.** The log's final
summary says the run passed; subsequent post-job cleanup reaches its final orphan
process cleanup. This is executed evidence, not source inspection or a Linux result.

| Revision | Existing push run / job | Build | Tests | Outcome |
|---|---|---:|---:|---|
| `24811b063eba4885822001f68e5655dfd83d079e` | [39277126786 / 118144332343](https://github.com/lesPrivilege/gleaner/actions/runs/39277126786/job/118144332343) | 172.15 s | 528 / 51 suites | 16 issues, all OriginalResolutionTests |
| `524fb80672cd2598bd5cad14ce5f483f8709d495` | [39278093014 / 118147164818](https://github.com/lesPrivilege/gleaner/actions/runs/39278093014/job/118147164818) | 155.67 s | 528 / 51 suites | Same 16 issues; repair absent |
| `6a39a13e6929bc7ab1ac24700a0af0929ad2bf44` | [39280023363 / 118152324799](https://github.com/lesPrivilege/gleaner/actions/runs/39280023363/job/118152324799) | 99.39 s | 541 / 55 suites, 21.647 s | Native tests passed; cleanup ended 15:44:51 UTC |
| `3ea45fdaaf9c67d5669c7150da4882a71b63adb9` | [39280465408 / 118153447592](https://github.com/lesPrivilege/gleaner/actions/runs/39280465408/job/118153447592) | 153.75 s | 541 / 55 suites, 33.346 s | Native tests passed; cleanup ended 15:54:47 UTC |

The latter two revisions have identical package manifests, dependency pins, source,
tests, experimental implementation and held-out Swift harness/labels. The intervening
changes are reports and JSON results. No manual workflow rerun was requested.

**Status metadata discrepancy:** when these completed logs were retrieved, GitHub
run/job/check endpoints and the public run page still reported `queued`, with no
runner or steps. The completed test logs are the basis for the passing execution
claim; an independently refreshed workflow status is recorded separately in
[validation-results.json](validation-results.json). Do not rewrite a reported
`queued` status into `completed` merely because the test log passed. The parent
reviewer now owns the narrow workflow-status watch; no redundant polling or manual
rerun is needed from this worker. Direct `mcp__codex_apps__github_fetch_workflow_job_logs`
requests with `repo_full_name: lesPrivilege/gleaner` and job IDs `118152324799` /
`118153447592` returned these logs; metadata endpoints alone did not reveal them.
An independent reviewer counted the pass records and checked final cleanup in both
saved decoded logs. Exact tool arguments and short non-sensitive evidence lines
are preserved in the machine record.

The source checkout SHA appears in each decoded log. SHA256 fingerprints of the
decoded logs, observed endpoint states and test counts are in that machine record;
raw machine-path logs are kept outside the public repository. The exact native
Swift compiler version is not printed. Testing Library Version 1902 is not a
compiler-version receipt.

## What the pass establishes

The original-reader suite now passes, including physical-path preservation,
arbitrary symlink/root-link refusal, parent-component rejection, unreadable/missing
distinction, bounded reads and injected mutation/replacement cases. The final
resolver source remains the independently reviewed Linux-tested implementation;
no policy was tuned after native results. Cycle 3 selection, correction, metamorphic
and held-out safety assertions also pass natively. Normal CI does not export a new
native relevance benchmark, so portable metric reports retain their own boundary.

Six opt-in tests were skipped: `walkTheBoardProject`, `walkTheReviewOfASeries`,
`walkTheFoldersHandedOver`, `drawEveryComponent`, `developmentTasksAndScale`, and
`measureOriginalModes`. These are not native passes.

Physical-path tests do not resolve core-shortened aliases, safe internal symlinks,
or bounded content returned from the same verified read. The existing native LogWatcher change-notification test and UI/model unit tests
also pass. The extra M1–M5 diagnostic probe, case-sensitive-volume comparison,
end-to-end app ingestion, rendered/manual human flows and migration/continuation
checks remain distinct obligations. See
[NATIVE-HANDOFF](NATIVE-HANDOFF.md) and [ENGINEERING-GATES](ENGINEERING-GATES.md).
No main merge, product-default adoption or release readiness is implied.
