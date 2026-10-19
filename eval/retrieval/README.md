# Convergence experiments

These are purposive synthetic cases, not a population estimate, a Finder study,
or a completed retrieval benchmark. Existing E0 remains untouched. The comparison
uses actual main `2648094610facfd1ae1805f52a9de282043c808f` and prototype
`44624ba8ed9c189fe903710d16f0b4f534ef8c0e`, with the identical Linux portability
patch described in [PORTABILITY](../../docs/retrieval-core/PORTABILITY.md).

`run.py` creates eight labeled tasks across software, media, design and research.
Gold is the explicitly intended logical output, including known unsupported cases.
The 24-member range intentionally dominates the file count, so the aggregate
cannot support a generalization claim. `heldout.py` was independently authored and
sealed before evaluation, with different museum, ecology and civic-engineering
contexts. Neither script implements extraction/search/ranking. They invoke the
real indexer and Catalog-backed CLI; no private logs or personal library are used.

## Reproduce

Build the runtime and baseline from PORTABILITY.md, then use fresh synthetic homes:

```sh
python3 eval/retrieval/run.py \
  --cli /workspace/gleaner-baseline/.build/debug/gleaner \
  --indexer /workspace/gleaner-baseline/.build/debug/gleaner-index \
  --runner 'docker exec gleaner-swift runuser -u gleaner --' \
  --home /workspace/gleaner-evaluation/baseline-new \
  --output /tmp/retrieval-baseline.json \
  --revision 2648094610facfd1ae1805f52a9de282043c808f --label baseline
python3 eval/retrieval/run.py \
  --cli /workspace/gleaner-cloud/.build/debug/gleaner \
  --indexer /workspace/gleaner-cloud/.build/debug/gleaner-index \
  --runner 'docker exec gleaner-swift runuser -u gleaner --' \
  --home /workspace/gleaner-evaluation/prototype-new \
  --output /tmp/retrieval-prototype.json \
  --revision 44624ba8ed9c189fe903710d16f0b4f534ef8c0e --label provisional
docker exec gleaner-swift runuser -u gleaner -- python3 eval/retrieval/heldout.py \
  --bin-dir .build/debug --revision 44624ba8ed9c189fe903710d16f0b4f534ef8c0e \
  --output /tmp/heldout.json
docker exec gleaner-swift runuser -u gleaner -- swift test -j 4
```

Use `--bin-dir /workspace/gleaner-baseline/.build/debug` for the independent
baseline run. Copy `RetrievalHeldOutTests.swift` to the baseline test directory to
repeat its four independently authored invariants, then filter that suite. The
extractor-only source and commands are in [CAPTURE-PROTOTYPE](../../docs/retrieval-core/CAPTURE-PROTOTYPE.md).

`run.py --variant renamed|irrelevant|duplicated` and `--scale N` prepare later
metamorphic/resource experiments; those development arms were **not run** in this
checkpoint. Independent held-out metamorphic checks did run. Scale and semantic
method comparisons wait for the object/selection contract to converge.

## Executed observations

| Measure | Baseline | Prototype | Interpretation |
|---|---:|---:|---|
| Intended objects present in index, development | 13/40 | 40/40 | Index presence, not captured-byte availability; 24 targets use proposed brace syntax |
| Development tasks with all desired exact versions usable | 3/8 | 4/8 | Range case succeeds; folder listing alone does not satisfy exact-version access |
| Same-request first-five precision | 1/5 | 1/5 | Correct spec first, four helper rows still require filtering |
| Independent same-request first-five precision | 1/5 | 1/5 | 19 total hits in each; target ranked first |
| Independent delivered-folder discovery | 6/6 | 6/6 | Both already enumerate explicit folder links |
| Independent folder first-page exact original availability | 0/5 | 0/5 | Files exist but captures remain `listed`; read-only Catalog does not complete them |
| Direct report-body `R1` search | Miss | Miss | No global content/section search was added |
| Scoped report → outline → section | Unsupported | Success | Two expansions after report selection; cross-report IDs refused |
| Independent Swift invariants | 4/4 | 4/4 | Durability, concurrent-session evidence, symlink boundary, duplicate evidence |
| Full portable suite, final | 306/324 | 328/346 | Both have the same 18 failed tests / 25 native compatibility issues |

Other retained failures: paraphrase absent from indexed words, omitted-stem
shorthand, ambiguous cwd-prefixed relative paths, glob recovery, and missing
original bytes. Unsupported glob rejection removes a fictitious row but is **not**
recall improvement. Exact historical selection, saved-copy recovery, separate
project contexts and partial-index indicators pass the independent cases.

Development timing: index 0.105 s baseline / 0.126 s prototype; mean query 0.087 s /
0.094 s across eight tasks. These include `docker exec` and process startup, one
small run, and are not scale estimates. Independent child peak RSS was 44,064 KiB /
44,332 KiB, a process maximum on its small workload, not whole-run allocation.
No memory result is inferred from the parent Docker client process.

The development harness reads up to 1,000 results to score exhaustive recall and
then separately scores the first five. Its verification expansion count is a
scripted effort proxy; it does not measure human filtering time or a successful
first-page workflow. Duplicate metrics count repeated logical rows, not inferred
semantic copies. Missing bytes can have perfect retrieval recall and still fail
the task. Uncertain relevance cases are named in each task's `note`.

Machine-readable results are under `results/`; executable and fixture hashes
identify what ran. Original logs/fixtures are generated in disposable synthetic
homes and are not committed. An initial harness call omitted the CLI's required
empty positional query, which was corrected before the retained results; errors
are now refused rather than misreported as zero capture coverage.
