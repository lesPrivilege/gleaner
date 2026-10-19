# Independent convergence review

2026-10-19. Baseline: `2648094610facfd1ae1805f52a9de282043c808f`.
This reviews an experiment, not an accepted product architecture. No source data,
provider adapters, credentials, or unrelated mounted repository were changed by
this reviewer. All new evaluation content is synthetic.

## What the current contracts settle

- Keep source evidence separate from interpretation. A file observation is not
  authorship, a delivery, or an approval. Current capture rules explicitly say so
  ([capture](../design/capture.md#two-kinds-of-evidence-kept-apart)).
- Preserve exact-version semantics, original versus saved-copy availability, and
  first-seen-later provenance. A broader result set must not silently substitute
  today's file for the selected historical bytes ([SPEC §5–6](../SPEC.md)).
- Corrections and byte-bound reviews survive rederivation. Equal bytes alone do
  not join works or projects ([projects and works](../design/projects-and-works.md)).
- Keep the app, CLI and MCP over one core. Main already contains the CLI/MCP work;
  the old branch is not a missing implementation to merge again.

## Decisions that need convergence

| Tension | Current source contract | Decision needed before claiming the user goal |
|---|---|---|
| Broad useful discovery versus library admission | SPEC §1 and capture's **Admission** leave observed files unsearched until a person keeps them. | Can a separately labelled candidate search return useful intermediate evidence without promoting it to a delivery? That is a product-scope decision; timestamp matching cannot settle it. |
| First actionable layer versus exhaustive matches | SPEC §10 returns every work matching one delivery's context, with named matches first; a reply's common context can still return many incidental files. | Choose what a first answer represents and how secondary material is expanded. Ranking, coverage, selection precision and effort need separate labels. |
| Logical findings versus path-backed works | SPEC §5.1a defines works through file paths and human joins; query-core explicitly deferred outline/content search. | A hash-pinned heading view is a safe experiment, but does not make message findings or cross-report decisions globally discoverable objects. Do not silently replace this broader goal with headings alone. |
| Versions versus relationships | SPEC §5.2 uses delivery events; evidence-and-lifecycle describes branches, renditions and reconciliations without ratifying a new schema. | Which relationships belong in the next scope, and what evidence authorizes them? A later timestamp is insufficient. |
| Broad extraction versus locator certainty | SPEC §9 resolves relative paths against the reply cwd and rejects placeholders. | Define when finite shorthand is explicit, when a relative path is ambiguous, and whether a constrained candidate proposal is preferable to automatic admission. |
| Agent parity versus read-only capture | Folder members begin as `listed`; the app completes their captures on action. Catalog opens the registry read-only and `read` requires a captured hash. | Decide how an agent obtains a verifiable member without falsely claiming old bytes or requiring an unexplained UI action. Read-only search alone cannot complete capture. |

The user's broader goal can supersede earlier deferrals, but the specific new
semantics still need to be explicit. The existing prohibition on inventing
authorship, delivery or a communicated ruling remains applicable.

## Independent experiment results

The independently authored held-out set has twelve real-CLI scenarios, with
separate capture, task recall, first-page precision, exact availability, scope and
effort measures. Baseline and prototype use the same Linux compatibility patch.
Fixtures and labels were authored before implementation inspection; after sealing,
only harness corrections were made: a synthetic future clock to make creation and
inode times precede delivery, the CLI's required empty-string query argument,
accurate rank/success naming (finding an object is not obtaining its bytes), and
executable hashes. No relevance labels were changed and
the prototype was not tuned on the held-out results.

| Locked artifact | SHA-256 |
|---|---|
| CLI fixtures/labels before harness corrections | `f753df9ab332f378978846eb38f2dbd80e7524c6a8929851a60ab710f80c4ad6` |
| Final executable CLI harness | `6f6b795716c6d3bf16c13ded7c0080e58ec9042d91cfddc0a49e4bfafe6d2bb2` |
| Swift invariants before synthetic-clock correction | `b7a316f1b91cfc3bddf071e8e32de79fbed044ed13877c679cd007559e4b5577` |
| Final executable Swift invariants | `a7405521b331eec91b7580fb95b11789f6aaf50d1f41c3ee6d241421c99fffd9` |

- In the same-reply selection scenario, both versions find the wanted report,
  rank it first, and still return four unwanted items in the first five: precision
  **1/5**, total **19**. Capture coverage is **1/1**. High coverage and first-rank
  success do not establish reduced filtering.
- Folder discovery finds **6/6** wanted map objects. The first page has **5/5**
  relevant results, but **0/5** provide an available exact original reference:
  their captures are still `listed`. This is not usable-original success.
- A report-specific section query misses in direct search in both versions.
  The prototype's report → outline → section path succeeds, takes two expansions
  after report selection, and rejects a section ID supplied to the other report.
- Glob-like shorthand no longer produces a fictitious literal item in the
  prototype, but still recovers **0/7** wanted objects. A shorthand with an omitted
  repeated stem and a workspace-prefixed relative path remain unsupported in both
  versions; these are misses, not evidence that the artifacts do not exist.
- Exact historical version selection, saved-copy recovery after a move, equal
  bytes in separate contexts, aborted/non-delivered exclusion, explicit partial
  source status and irrelevant-evidence invariance pass in both versions.
- Four independent Swift invariants execute and pass on each version: durable
  corrections and byte-bound reviews through rederivation/partial input; distinct
  simultaneous-session evidence; no delivered-directory traversal through an
  external symlink; and duplicate mentions keeping one review object with both
  evidence anchors.

These findings support bounded progressive access and safer rejection of patterns.
They do not establish the complete useful-object goal, a general retrieval gain,
or superiority to Finder or an agent library. Latency includes process startup;
the corpus is purposive and small. Full native UI/filesystem acceptance remains a
Mac handoff, not a Linux result.

Reproduce against built executables, with Python and Swift in the same environment:

```sh
python3 eval/retrieval/heldout.py --bin-dir .build/debug --revision REVISION --output heldout.json
swift test -j 2 --filter RetrievalHeldOutTests
```

Machine-readable results are in `eval/retrieval/results/heldout-baseline.json`,
`heldout-provisional.json` and `heldout-swift.json`. Each CLI result records its
fixture and executable hashes. The provisional source revision identifies the
uncommitted experiment over `b4fdad1`; executable hashes identify what actually ran.
The parent subsequently committed that implementation as `44624ba`; both
executable hashes exactly match its checkpoint benchmark run. The recorded
pre-commit labels are retained rather than rewriting the experiment's history.
The baseline is main plus the separately recorded portability patch, not a weaker
replacement algorithm. This small set measures repeated-path duplicates; it does
not establish correct grouping of semantic duplicates or renditions.

## Implementation review limits and follow-up

Source inspection confirms thin adapters and version-bound section IDs; it does
not execute macOS behavior. The provisional section parser deliberately supports
only a bounded subset of Markdown headings. Its title extraction is not semantic
finding/ruling recognition.

Pagination's generation detects completed reindexing, not a snapshot or every
correction made between pages. `Catalog.find` reads generation before separate
artifact/correction reads, while `Registry.record` advances it only after a run;
concurrent indexing can therefore expose mixed state before the generation changes.
Keep this limitation explicit; do not describe the generation guard as consistent
snapshot pagination. The new **1,000** result cap also changes the old public
`find(limit:)` contract, which accepted every positive limit. This is reasonable
for a bounded adapter experiment but requires an explicit compatibility decision
and continuation instructions before formal adoption. Outline reads
through the verified-byte path before applying its four-MiB parsing bound, so the
bound limits returned/parsed content, not necessarily total source I/O.

Native structure remains narrower than the requested long-term evidence model:
`SessionLog` retains sessions, final-reply parts, request times and record anchors,
but does not expose a general role/tool-call evidence graph. No schema expansion
should be presented as necessary until a concrete retrieval failure needs it; no
claim of fully preserved native event structure is warranted by the current types.

No model comparison has been run. Lexical versus semantic assistance, assembly
relations, candidate-search selection and human effort are future experiments
after the object/evidence contract converges. Paid-model trials are not implied.
