# Second convergence cycle

This cycle continues checkpoint `7e004a72920d0648c8d7ce38bdb4da86eab4926c`.
Remote main was re-fetched on 2026-10-19 and remains
`2648094610facfd1ae1805f52a9de282043c808f`; the old query branch remains integrated.
No new production behavior, migration, ontology or UI decision is adopted here.
Executable source checkpoint: `3987797`. Exact full revision, source hashes and
final regression results are recorded in [validation-results.json](validation-results.json).

Read the [method alternatives](METHODS.md), then the independent evaluation and
native-failure classification in this directory. The first checkpoint's
[intent/spec/code matrix](../CONVERGENCE.md) still governs. Current-file-first detail
and independent delivery/review/publication states were already settled contracts;
this cycle does not ask to reopen them.

## Comparison design

All candidates use existing GleanerCore identities and evidence. The development-only
`GleanerRetrievalExperiments` target is not linked by the app, CLI or MCP. No provider
adapter, database schema, correction, review or capture behavior changes in this cycle.

| Question | Minimal alternatives | Evaluation boundary |
|---|---|---|
| State selection | Explicit requested state; disclose independent references; naive newest-delivery negative control | The negative control is **not** main's search behavior. No claimed improvement over main from defeating it. Current working intent can remain unknown even when current bytes at a chosen path are readable. |
| First layer | Existing `Organization.search`; focus its existing named tier; group by proven native reply | Same candidates/matcher/order within tiers. Grouping is presentation, not identity or new relevance. All matches remain reachable. |
| Listed original | Unverified path; checked metadata; bounded hash of current bytes | Historical capture hash and current observation remain separate. No capture completion or registry writes. This experiment resolves/hashes; it does not yet return file content. |
| Report ID | Existing report-local heading substring; exact leading identifier | Selected captured report/version only. No global body search, inferred finding identity or ruling. |

Development labels are in
[`DevelopmentMeasurements.swift`](../../../Tests/GleanerRetrievalExperimentTests/DevelopmentMeasurements.swift).
Three tasks share a deliberately controlled nine-object work package to isolate
name, project-context and request-only matching. A fourth uses complementary design
outputs with construction files in one reply. These are comparisons, not four
independent domains or an estimate of general user relevance. The held-out evaluator
authored a separate corpus and sealed its label hash before policy evaluation.

First-layer object precision counts **all members** of visible groups; reporting
one relevant group as 100% precision would conceal irrelevant members. Directly
selectable relevant objects counts singleton results. Candidate preservation is
checked independently. Expansion counts are conceptual selections unless a result
explicitly records executed API calls; current grouping responses include all
members and do not demonstrate a smaller payload.

The final scale fixture has 1,000 Markdown documents with distinct contents, 100
overlapping synthetic sessions in one workspace and two query shapes. Actual
recorded observations and captured hash counts are included in the JSON: document
count alone is not the whole index workload. Thirty warmed iterations per policy/query report p50/p95/max wall time for
in-memory shared search plus experimental response construction. Indexing and
Organization loading are timed separately. This is a small documented workload,
not a library-scale or Finder comparison. Timings must run apart from other builds.
Policies run in fixed order; small timing differences are not statistically established
advantages. The wrapper records whole-invocation child maximum RSS, not per-query
or summed process memory. Serialization and current-original verification are absent
from the in-memory query timings.

The initial development result is retained as `development-results-initial.json`.
Method review strengthened the candidate/reachable-partition check against direct
`Organization.search`, replaced score-only metamorphic comparison with normalized
result identity/order comparison, and made scale contents distinct while recording
actual observation counts. Those are harness changes; no policy was tuned. The final
development result and timings supersede the initial calibration run.

Final Linux debug workload: **1,000 distinct captured hashes, 100,000 recorded
observations**, 168,370 input bytes; indexing **4.817 s**, Organization load **1.432 s**.
The high observation count comes from the overlapping-session fixture, not from
1,000 independent historical edits. Broad-query p50/p95 are **19.314/20.252 ms** for
the shared baseline, **19.571/19.973 ms** for named focus and **20.391/21.014 ms** for
reply groups. Whole skip-build invocation child maximum RSS is **252,540 KiB**;
that is not per-query memory. The narrow name query retains ten core candidates
because the same reply mentions nine companion outputs; presentation does not
change candidate matching. Exact values and all timing boundaries are in
[development-results.json](development-results.json) and
[resource results](development-resource-results.json).

Separate original-read cost measurements use five repeated observations per size,
with uncontrolled cache warmth: hash medians **0.132 ms / 0.808 ms / 11.157 ms** for
**4 KiB / 1 MiB / 16 MiB**, reading exactly those content sizes. Path and metadata
modes read zero content bytes. A known-oversize file refuses before content I/O.
[Original cost results](original-cost-results.json) do not claim cold-cache latency
or process memory bounds.

## Reproduction

Use the existing official Swift 6.2.4 Linux container described in
[PORTABILITY.md](../PORTABILITY.md), as its unprivileged user. Sources and labels are
synthetic. The benchmark is opt-in so ordinary test/CI runs do not execute timings.

```sh
docker exec gleaner-swift runuser -u gleaner -- swift test -j 4 \
  --filter 'RetrievalPolicyTests|ExperimentalSectionLookupTests|OriginalResolutionTests|Cycle2HeldOut'
docker exec gleaner-swift runuser -u gleaner -- python3 \
  /workspace/gleaner-cloud/eval/retrieval/cycle2/measure.py
docker exec -e GLEANER_CYCLE2_MEASURE=1 \
  -e GLEANER_CYCLE2_RESULTS_DIR=/workspace/gleaner-cloud/docs/retrieval-core/cycle2 \
  gleaner-swift runuser -u gleaner -- swift test -j 4 --filter OriginalResolutionMeasurements
python3 eval/retrieval/cycle2/native/run.py --repository /workspace/gleaner-baseline \
  --output docs/retrieval-core/cycle2/native-probe-baseline.json
python3 eval/retrieval/cycle2/native/run.py --repository /workspace/gleaner-cloud \
  --output docs/retrieval-core/cycle2/native-probe-candidate.json
```

The independent evaluation records its exact test filter, export variable and label
hash. Native probes link the built actual core; they do not replace it. A Mac check
requires an authorized separate checkout and synthetic home. Cloud execution is
not evidence of macOS, UI, FSEvents or APFS behavior.
