# Cycle 2: bounded methods for four open questions

Research options, not product rulings or an accepted architecture. Read on 2026-10-19 against
remote main `2648094610facfd1ae1805f52a9de282043c808f`. The current branch's section/pagination
work remains an experiment. This note proposes no production edit, migration or new ontology.

The governing contracts are [review: independent states and current document first](../../design/review.md),
[query core](../../design/query-core.md), [capture](../../design/capture.md),
[convergence](../CONVERGENCE.md), and its [independent review](../CONVERGENCE-REVIEW.md).
[Organization](../../../Sources/GleanerCore/Organization.swift) already returns one result per
`Work`; files become one work only through a person's join. Collections group distinct works.
`Work.latest` selects the file of the newest delivery; it does not establish an authoritative
working version. Existing UI current-file access and CLI exact-version access answer different
questions. Neither should silently replace the other.

## Source mechanisms and transfer limits

| Primary source | Mechanism that transfers | Assumption, cost or limit |
|---|---|---|
| [Git's three trees](https://git-scm.com/book/en/v2/Git-Tools-Reset-Demystified) | Working content, proposed snapshot and committed snapshot are separately addressable. | Useful separation, not a mapping from commits to delivery, review or publication. Git status cannot prove those acts. |
| [W3C PROV-DM](https://www.w3.org/TR/prov-dm/) | Generation, use, attribution, derivation and communication describe distinct evidence. | Preserve the distinction using existing native records; adopting RDF or treating temporal overlap as causation does not follow. |
| [W3C DCAT 3 versioning](https://www.w3.org/TR/vocab-dcat-3/#versioning) | Version chains and an explicit current-version link are separate relations. | A latest timestamp does not supply that link. A new persistent “current” choice would need an owner ruling; this note does not propose one. |
| [SQLite FTS5](https://www.sqlite.org/fts5.html#the_bm25_function) | BM25 and weighted columns offer lexical relevance beyond newest-first ordering. | Tokens and corpus statistics matter; content synchronization is additional derived-index work. A ranking score is not evidence of authority. |
| [Anthropic contextual retrieval](https://www.anthropic.com/engineering/contextual-retrieval) | Retrieval units lose meaning when separated from their parent; lexical and semantic retrieval have complementary misses. | Native project, report, turn and role context is available without generated summaries. The provider's measured gains and paid implementation do not establish Gleaner gains. |
| [Elastic result collapse](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/collapse-search-results) | Rank a representative under a known group key and expand members on demand. | Group identity must already be sound. Expansion has query cost; grouped counts and raw hit counts differ. No Elasticsearch dependency is needed. |
| [SQLite read-only open](https://sqlite.org/c3ref/open.html), [isolation](https://www.sqlite.org/isolation.html) | Read-only connections prevent registry writes; one read transaction can make related database reads consistent. | A completed-index generation is not a snapshot of corrections or concurrent indexing. Database isolation does not freeze external files. Do not use `immutable=1` on a changing library. |
| [W3C Web Annotation selectors and states](https://www.w3.org/TR/annotation-model/#selectors) | Identify a source representation separately from a selected quote or range. Positions are fragile across edits; byte offsets differ from character offsets. | Bind a section range to verified source bytes. A repeated quote can have multiple matches. An anchor identifies evidence, not a finding's meaning or disposition. |

These sources support mechanisms and failure analysis. The recommendations below are local
inferences; no external system's benchmark is substituted for Gleaner's measurements.

## 1. Which content should a task select?

Already settled: generated, readable now, reviewed and published are independent. Verdicts and
publication marks bind to bytes. The native detail shows readable current bytes with their actual
relationship to a delivery. “Last reviewed” means the last verdict, which can be rejection;
it does not mean approved. A publication mark does not prove approval or current relevance.

Two minimal alternatives for query presentation:

| Alternative | Mechanism | Cost and failure mode |
|---|---|---|
| **Explicit task selection** | A caller asks for current readable content, the last delivered version, the latest review's bytes, or publication marks. Select within the already identified work; return the basis and existing evidence references. | Small deterministic projection over existing records. Current file checking adds I/O. A missing requested version remains unavailable; substituting another role would answer the wrong question. |
| **One work, separate references** | Return a compact work result, its current-file observation if requested, and separate references to the last delivery, latest review and publication marks. Expand only the chosen reference. | More response fields and an extra selection, but makes disagreement visible without four duplicate results. Multiple publication marks or multiple joined files may remain choices. |

Neither requires inferring a canonical “current working” version. If a work joins a draft and
final path and both are being edited, current bytes at each path are facts; which path is intended
for continued work may be unknown. An explicit future user choice would be governance, beyond a
ranking experiment. Durable corrections remain durable; a query must not create one.

**Counterexample/experiment.** Deliver A, approve A, publish B without approval, then edit C on
disk and later roll back to A. Ask each of the four tasks at each step, with A also missing in one
variant. Require zero state substitutions and correct evidence/hash associations. Measure number
of selections and bytes read separately. Also reverse import order while retaining native event
order. The experiment can choose a cheaper projection; it cannot decide which task should be the
default or whether a person should gain a new “working version” control.

## 2. How should the first layer be selective?

Use actual `Organization.search` as the control: project/folder context, named-first order and
one result per established work already exist. Applying generic duplicate collapse again would
not improve it. Candidate admission and ordering are separate experimental axes: a ranker cannot
recover an observed file excluded from its input, while broader discovery need not create a review
obligation. Preserve source-off rules and authorized scope before selecting top results.

| Alternative | Mechanism | Cost and counterexample |
|---|---|---|
| **Small deterministic rerank** | Keep the shared candidate generation and work identity. Compare explicit name/path/role matches, native parent context and the requested task's state; use recency as a tie-breaker rather than a status. Emit a short match basis. | Little storage change and readily ablated features. A blanket “final” or document-extension boost wrongly buries the intermediate script sought by a repair task. Parent context shared by 100 helpers cannot alone distinguish the wanted report. |
| **Existing-context presentation groups** | Present matches under an existing collection or a proven native reply boundary, retaining each work and its individual rank. Show a bounded member preview and expand the rest. Unassigned matches remain accessible. | Can reduce visual/agent expansion burden without joining files. Group headings are not logical-object identities. A folder/timestamp cannot substitute for an absent reply key, and a collapsed 56-item series may conceal the one requested member. |
| **Scoped fielded lexical ranking** | Build a rebuildable FTS projection of existing native units, with separate title/path, project/collection and request/reply fields. Rank within the authorized scope; map hits back to existing work/delivery references. | Additional index/update/tokenization work. Avoid combining words from unrelated deliveries to fabricate a match. Exact identifiers need lexical treatment; genuine paraphrases may still miss. Stale context or duplicate evidence can distort scores. |

Prefer comparing the first alternative before paying for an FTS migration. The second is an
independent presentation comparison, not proof of better recall. If a diverse held-out paraphrase
set still fails after native contextual retrieval, compare an optional local semantic candidate
arm against the same lexical arm and bounded rerank budget. Similarity cannot assign delivery,
review or publication status. There is no present evidence warranting a mandatory model.

**Experiment.** Label tasks separately: inspect the finished specification, debug its generator,
find all series members, recover an intermediate design, and inspect an earlier rejected version.
Include unnamed-but-useful files, deliberate user-kept intermediates, repeated copies, unrelated
same-hash works and misleading “final” names. Report capture/admission recall separately from
recall@k, precision@k, unique useful works, hidden-member count, expansions and latency. Compare
fixed candidate sets first, then vary admission. Added irrelevant files and duplicated evidence
must not improve a work's rank merely through repetition. The acceptable default balance of
observed evidence versus delivered/kept work remains a product choice, even with measured curves.

## 3. How can a listed, uncaptured original be accessed read-only?

The stored delivery hash being null means exact historical bytes are unknown. Present readability
can still be useful. Existing `read` must retain its exact-version meaning; neither a successful
current read nor matching size/date may fill the historical hash or change provenance.

| Alternative | Mechanism | Cost and failure mode |
|---|---|---|
| **Locator and current status only** | Resolve the recorded locator within authorized roots; return whether it is now a readable regular file, with observation time, while keeping historical availability unchanged. | Lowest I/O; sufficient for another authorized viewer to open. The next open can see changed bytes, and an agent still lacks bounded content. A directory is described as a directory, never read as text. |
| **Explicit bounded current read** | Read a selected current regular file without calling capture completion, review, staging or index writes. Return the requested range and current observation, clearly distinct from the delivery reference. | Useful progressive access without snapshot storage. A range hash identifies only that returned range; do not label it a whole-file hash. Concurrent edits require a defined refusal/retry policy and cannot be made historical by a timestamp. |
| **One-call verified current bytes** | For a bounded-size file, read into memory once, hash those bytes and return content/range from that same buffer. Check the open file's metadata around the read; refuse detected drift. Keep everything transient. | Whole-file I/O/memory in exchange for a clear byte reference, still no historical capture. Metadata checks detect ordinary races, not an atomic filesystem snapshot. Oversize files must fall back explicitly or refuse, not silently claim verification. |

All three need locator authorization at the actual open, including symlink behavior; a previously
checked path is insufficient if replaced. Resolve from recorded context, not duplicated string
joins; no shell glob expansion, command execution or fallback whole-disk search. A missing moved
file stays unresolved unless an existing authorized locator mapping identifies it. Preserve
missing, unreadable, source-off and outside-scope as distinct results.

**Experiment.** Start with listed-but-unhashed files and compare registry rows, correction/review
state, capture store and staging contents before/after each operation. Exercise replacement,
in-place rewrite, restored size/mtime, symlink escape, missing original, denied read, directories
and large files. Report bytes read as well as returned. Test database consistency separately from
file races. Byte hashes must describe exactly what was read, never a delivery never captured.
Whether bounded current content belongs in the initial response or requires an explicit expansion
is a product/API decision; a test can quantify its cost, not authorize silent substitution.

## 4. How should report-section IDs be scoped?

Keep this separate from global artifact search and finding governance. `R1` is a label inside a
particular report/version; it can recur across projects, rounds and even within one report. A
section can contain a proposal, quoted old ruling or rejected observation. Extraction supplies no
authority relationship. The [existing section experiment](../QUERY-PROTOTYPE.md) recognizes a
bounded Markdown heading subset and already binds byte ranges to a selected captured version.

| Alternative | Mechanism | Cost and counterexample |
|---|---|---|
| **On-demand scoped outline** | Select the report, then match complete heading identifiers/titles and return version-bound byte ranges with parent-heading context. | No new persistent index; parsing cost per read. `R1` must not accidentally match `R10`; duplicated R1 headings return distinct scoped matches. Headingless findings remain undiscovered. |
| **Scoped literal evidence lookup** | Within the selected exact report, find identifier/phrase occurrences and show bounded surrounding text and heading context, without calling them findings. | Handles prose/tables with little indexing work, but mentions and quotations are false positives for “the finding.” All ambiguous occurrences remain visible. |
| **Derived per-version section index** | Persist the same parser's ranges under report/version hash and parser version; invalidate/rebuild that derived data when either changes. | Faster repeat lookups at storage/update cost. A moved heading is a new range, not automatically the same finding across revisions. No durable review state belongs in this cache. |

**Experiment.** Repeated IDs across reports/projects, duplicate headings, R1/R10, nested sections,
quoted older decisions, fenced examples, CRLF/Unicode and edits before a section. Measure scoped
precision/recall, exact-range correctness, parse I/O and expansions to evidence. The existing
prototype's parse bound currently follows full verified-byte loading; measure total I/O rather
than reporting its parser limit as an I/O limit. Zero cross-report/version substitutions is a
correctness gate. Persistent finding identity, cross-round links and who may designate a ruling
need explicit product decisions; neither a heading parser nor a similarity score settles them.

## Comparison discipline

Run these as independent arms over the same synthetic relevance labels and actual shared core.
Keep a separate ambiguous label when the requested authority or working path cannot be inferred.
Use independently authored held-out workspaces, not only renamed copies. Report failures by task
and domain, results under stale/partial index state, p50/p95 latency, peak memory, and read volume.
A response's completeness pertains to its scan/source/query scope, never the whole filesystem.
No alternative is selected by this note; it defines what a bounded comparison can establish and
what remains with the product owner.
