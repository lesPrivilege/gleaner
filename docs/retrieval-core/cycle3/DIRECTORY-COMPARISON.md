# Cycle 3: independent review of the directory comparator

Reviewed 2026-10-19 against
[`compare_directories.py`](../../../eval/retrieval/cycle3/compare_directories.py)
and its [recorded results](directory-comparator-results.json). This review checked
source and recomputed every row's precision, recall and open count from the JSON;
it did not rerun the experiment. No selection policy was changed after evaluation.

This is a four-task **development comparison**, not the independently sealed
selection-policy held-out set, a Finder trial, or a human-effort measurement.
The same author constructed these tasks and scripted plans; there is no separate
pre-label script-freeze record. Runtime selection does not consult labels.

## Actual task results

Both arms show at most five objects and open every shown candidate. Precision is
wanted paths divided by shown paths; recall is wanted paths shown divided by all
wanted paths. These are path-relevance metrics, not historical-version equivalence
or a claim that a reproduction was executed successfully.

| Task and supplied terms | Directory: wanted/shown; recall; opens | Shared CLI: wanted/shown; recall; opens | Observed distinction |
|---|---|---|---|
| Read the proposal (`riparian proposal`) | 1/1; 100%; 1 | 1/3; 100%; 3 | Body/path search isolates the proposal. Shared request context also matches inputs and a generator: CLI precision is 33.3%. |
| Inspect review and reproduction (`boron review`) | 2/3; 100%; 3 | 2/3; 100%; 3 | Both include the two wanted objects and optional raw data: precision is 66.7%. |
| Open the diagram (`copper transit`) | 1/1; 100%; 1 | 1/1; 100%; 1 | Terms occur only in the native request. Directory search needs its folder fallback; CLI finds the captured diagram directly. |
| Open new current survey (`estuary access`) | 1/1; 100%; 1 | 0/1; 0%; 1 | File was created after indexing and has no delivery log. CLI's project fallback opens unrelated captured background. This is an admission/freshness boundary, not an indexed-artifact ranking miss. |

All eight CLI reads returned captured text. That includes the irrelevant background
in the last row; readable evidence alone does not complete the task. Directory
reads inspect current originals and record their hashes. CLI reads address captured
delivery versions. The report does not compare hashes between arms or test moved,
changed or unavailable historical originals.

## Fairness, scope and cost limits

- Both arms receive the same literal terms and known project. Directory scope is
  the exact generated root; CLI scope is its unique project name. Neither receives
  target basenames for selection. Both use one broad overview fallback only after
  an empty search. Labels are consumed after both query and open plans finish.
  The descriptive task prose is reported but interpreted by neither arm.
- The directory arm performs real recursive `rg` path/body search, followed by
  alphabetic ordering. The CLI calls actual shared-core `find` and `read`; it can
  match native request/reply context. Those capabilities intentionally differ.
  Provider logs are not searched by the directory arm, and provenance tasks are
  not compared here. Unknown-location discovery is also untested.
- All filesystem searches stay under the four disposable generated project roots.
  Arguments are arrays, literal search terms follow `--`, and no source content
  is executed. `rg` is not asked to follow symlinks. The 100-file/32-KiB-per-file
  checks happen **after enumeration**, before body searching. They are a fixture
  contract, not a hard discovery budget or secure resolver for changing, untrusted
  trees. Body searches rewalk the root; concurrent replacement and symlink races
  are untested. These fixed fixtures contain no symlinks or dependency trees.
- Each directory task uses one enumeration and two literal body searches, then
  opens 1/3/1/1 files. CLI uses 1/1/1/2 queries, then opens 3/3/1/1 captured
  versions. These operations have different costs; counts are not human effort.
  Directory opens allow 32 KiB versus CLI's 4-KiB read cap, but every observed
  file is at most 65 bytes, so this mismatch does not affect these rows.
- Directory stdout counts filenames from enumeration/search and excludes opened
  content; CLI stdout includes JSON metadata and read responses. Comparing those
  totals as payload efficiency would be misleading. The directory body-scan byte
  field is a corpus-size upper bound, not measured I/O. There is no query latency,
  memory, cold-cache or end-to-end comparison; `rg` runs on the host and CLI calls
  cross Docker. The recorded 0.104-second index run includes that process boundary
  and admitted eight deliveries from four logs before the ninth file was created.

## Reproduction

From the repository root, with `rg`, Python 3, the `gleaner-swift` container and
the debug CLI/indexer built, run:

```sh
python3 eval/retrieval/cycle3/compare_directories.py --output /tmp/gleaner-cycle3-directory-results.json
```

The script creates and removes its own synthetic home under
`/workspace/gleaner-evaluation/cycle3`; it does not scan a personal library. Tool
versions, binary hashes and index health are in the JSON. The measured run used
ripgrep 15.2.0. Index identity and time are expected to change on reproduction.

These examples justify retaining body-search, native-context and current-discovery
capabilities as distinct design considerations. They do not establish a universal
winner, an improved first-layer policy, or overall superiority to Finder or an
agent's raw library.
