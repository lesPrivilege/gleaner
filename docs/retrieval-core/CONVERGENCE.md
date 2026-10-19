# Convergence checkpoint 1

2026-10-19. This is a decision map and experiment checkpoint, not a finished design
or a release-readiness assessment. The later user instruction puts reconciliation
before formal implementation. Code already written is retained as an explicitly
provisional experiment. No private logs or conversations were consulted.

## What changed the starting premise

The fetched baseline is `2648094610facfd1ae1805f52a9de282043c808f`, not the earlier
audited `3bcb6d7`. Main already contains `feat/query-core` at `cdfe6f4`, the six-call
CLI/MCP, a synthetic-home indexer, shared app/Catalog search, contextual parent
folders and named-hit-first ordering. The old branch is reuse history, not a
missing feature branch to merge. See [branch map](BRANCH-MAP.md).

The public design record also already rejected a narrow fix for episode filenames:
[capture's opening](../design/capture.md) explicitly replaces folder/range and
numbered-episode drafts with provider-independent session observations. A new
range parser can establish feasibility for an explicit notation; it cannot stand
in for the broader capture/topology problem. That conflict changes its priority.

## Intent → declaration → implementation → unresolved decision

Rows distinguish the current supplied goal from historical product scope. Links
name the declarations and source, rather than treating every old document as an
equally current requirement. Implementation statements are source inspection
unless the experiment section records execution.

| Intent / question | Public declaration and evolution | Actual baseline | Gap and next decision |
|---|---|---|---|
| Return useful logical work, including intermediates | [SPEC §1–3](../SPEC.md), [capture admission](../design/capture.md), [review](../design/review.md) | Explicit deliveries and human-kept observations enter searchable `Artifact`/`Work`; candidates stay under Observed | Current goal is broader than admission. Rule whether observed candidates become discoverable in a separate evidence tier; never relabel them delivered. |
| Preserve native session evidence | [SPEC §8](../SPEC.md), [SessionLog](../../Sources/GleanerCore/SessionLog.swift) | Provider/session/cwd/request/reply parts and original log lines survive; provider adapters deliberately omit most tool transcript content | Tool-call IDs, delegated findings and message-only decisions are not a complete normalized event model. Determine minimum useful anchors with task experiments before adding schema. |
| Project is first-class, location is not identity | [projects/works](../design/projects-and-works.md), [architecture alternatives](../design/architecture-precedents.md) | `Organization` has derived and user projects, moves/combines, work units and correction provenance; Git checkout/repository recorded separately | User-created project keys are stable; derived keys remain paths. Multi-repo memberships/folder rules and moved-log reconciliation are open, not solved by another project table. |
| A logical object may be a report section | [structure](../design/structure.md), [query-core](../design/query-core.md) | File/work retrieval and bounded exact-byte reads; native Markdown headings exist, but no global section object index | Scoped hash-pinned section prototype can reduce reading. A persistent finding, its status and cross-report relation need separate rulings. `R1` alone is not identity. |
| Same bytes do not merge meaning | [SPEC §5.2](../SPEC.md), [Organization](../../Sources/GleanerCore/Organization.swift) | Shared content store, separate path/context identity; joins require human correction | Retain this. Similar names/hash may support a suggestion, never accepted lineage or cross-project merge. |
| Current useful content first | [review: current document first](../design/review.md#the-current-document-first), [query-core exact read](../design/query-core.md) | Native preview may show labeled current bytes; CLI `read` stays tied to selected capture and refuses substitution | This is a deliberate surface difference, not necessarily a defect. Rule agent access to explicitly current observations separately from historical-version reading. |
| Discovery broad, first layer selective | [capture ordering](../design/capture.md), [SPEC §10](../SPEC.md) | Structural cache exclusions, folded folder rows and person-openable ordering in `Listing`; `Organization.search` returns all matches, named matches before mentions | Search is flatter than outline browsing. Measure noise and expansion before selecting focused-default, evidence-tier grouping or reranking. File type alone cannot decide utility. |
| Query uses remembered project and role | [SPEC §10](../SPEC.md), [SearchTests](../../Tests/GleanerCoreTests/SearchTests.swift), commits `32e8594`, `2648094` | Shared search includes ancestor folders inside project/checkout and corrections/collections | Historical basename-only bug is already addressed. Vocabulary mismatch and role cues remain empirical questions; no new retriever justified merely by old audit. |
| Folders/ranges and relative paths | [capture](../design/capture.md), [MentionExtractor](../../Sources/GleanerCore/MentionExtractor.swift), [Bundles](../../Sources/GleanerCore/Bundles.swift) | Explicit folders expand via bounded metadata walk; relative code-span `exports/` missed; pattern text may become a literal nonexistent target | Separate syntax recognition defects from ambiguous intent. A project-prefixed relative path has two possible meanings; existence does not authorize silently repairing it. |
| Useful originals, exact revisions | [SPEC §5–6](../SPEC.md), [Catalog](../../Sources/GleanerCore/Catalog.swift) | Capture times/provenance, exact hash checks, saved-copy fallback, git recovery proposals; folder members listed without reading bytes | An indexed member may be physically present yet lack a hash-backed version in read-only Catalog. Rule progressive agent byte access without silently writing/indexing or falsifying delivery-time bytes. |
| Durable corrections, rebuildable derivation | [projects/works corrections](../design/projects-and-works.md), [Registry](../../Sources/GleanerCore/Registry.swift) | Separate correction/review tables, write gate, migration backup, reread cursors, capture retention | Existing extractor changes require version/reread handling. Prototype syntax changes have no version bump yet and are fresh-home experiments only. Moved anchors remain unresolved rather than transplanted by similarity. |
| Distinguish missing result from incomplete index | [query-core freshness](../design/query-core.md), [Registry.index](../../Sources/GleanerCore/Registry.swift) | Every Catalog answer includes library/generation/scan/source status; absent/off/partial/unknown counts | This is evidence of last completed scan, not current source completeness. Need experiment for concurrent page reads and a design rule for ordinary quiet health indicators. |
| Thin CLI/MCP | [SPEC §14](../SPEC.md), [MCP adapter](../design/mcp-adapter.md) | Six tools/commands share Catalog; read-only except verified cache handoff; official pinned SDK speaks legacy protocol | New project/outline/section/paging prototypes extend an explicitly deferred contract. Must decide names/scope/compatibility before product adoption. Latest protocol is not automatically the right upgrade. |
| No inferred authority or decisions | [claims in replies](../SPEC.md#62-claims-in-replies), [editorial exploration](../design/project-knowledge-explorations.md) | Replies are data; review/published marks are human, hash-bound acts | No implementation may invent an uncommunicated ruling. A section index is navigation, not interpretation of decision authority or supersession. |
| Reduce effort vs Finder/raw library | [E0](../design/evaluation-e0.md), [evaluation results](../../eval/results/2026-10-18/report.md) | Historical scripted raw-search comparison exists with locked policies and specific task families | Not a human Finder study, not evidence for current selected-object usefulness. Preserve its results and run a distinct labeled experiment; no superiority claim. |

### Refined requirements, without prematurely choosing boundaries

The parent's later generalized reconciliation sharpens the questions below. These
requirements do not contain private source material. They supersede any inference
that early delivery-only scope or a historical proposal permanently bounds the goal.

| Refined intent | Concrete code evidence | Explicit unresolved question |
|---|---|---|
| Broad discovery coexists with strict delivery evidence | `Organization.candidates` and `candidates(in:)` retain observations separately; `search` iterates `works` only; `Keeping` admits an observation through a person's correction | How should searchable intermediate/reusable material appear without a Keep prerequisite or a false delivery label? One query with evidence tiers or an explicit scope? |
| Latest observed, current working, last delivered, last reviewed and published can differ | `Work.latest` selects the newest delivery's file; `Present` describes checked current bytes; `Review.standing`, `Reviews.verdicts` and `Reviews.published` evaluate independent hash-bound records ([Review.swift](../../Sources/GleanerCore/Review.swift)) | What establishes “current working” beyond disk observation? Which state does each task request, and how is an unset state shown? Never collapse these into one current boolean. |
| Multiple versions need not dominate ordinary review | Versions follow delivery events; native detail can show current bytes; `toReview` depends on collections/verdicts rather than every indexed file | Which useful state is the default per human/agent task, and what history expands on demand? Do not turn every write into an obligation. |
| Project identity is not any one source/container identity | `Project.Origin`, correction-backed moves, repository/checkouts and session cwd are separate, but derived project keys are folder paths | When must one project span folders/repositories/provider projects, and which accepted identity survives moves? A shared path or hash is evidence, not the answer. |
| Logical names and assignments are durable and reversible | [Corrections.swift](../../Sources/GleanerCore/Corrections.swift) and user projects/work-unit names survive rereads; `Work.name` is still `latest.name` | Is a work alias needed independently of filename and project/unit name? How do scoped aliases survive changed extraction anchors without inventing a relationship or ruling? |
| Reset meanings are explicit | `undoAllCorrections` removes organization corrections; `ContentStore.clearStaging` clears disposable copies; Registry reread retains captures; reviews have separate undo | Define reindex, reset organization, clear staging and delete preserved bytes independently. What stays unresolved when a source disappears? Never one undifferentiated reset. |
| An object can span sections and related messages | Current `Evidence` preserves file-mention excerpts/anchors; section prototype is a view over one captured document | What minimal relation joins a passage to a communicated decision or related message? Which native anchors and human confirmations are required? An uncommunicated ruling has no such relation. |
| Absence, stale index, parse gaps and negative retrieval differ | `Catalog.Index` exposes scan/source state and failures carry it; parsing counts unknowns/partial logs | What scope and freshness evidence supports a negative for the selected task? How is unavailable original content separated from missing index evidence? |
| Human review and agent reuse share semantics with different projections | Organization and Catalog share works/search; native preview can use labeled current bytes while Catalog `read` requires an exact capture | What explicit current-observation access preserves the same meaning without bypassing immutable version checks or silently writing via read-only tools? |

There is **no adopted requirement** for a fixed four-layer command taxonomy,
CLI-before-MCP sequence, pointer-only storage, snapshotting every change, or full
historical-text reconstruction from tool logs. Existing shared CLI/MCP and the
size-governed content store are relevant constraints, not a reason to reopen
settled work. No fixed model, vector database, graph architecture or autonomous
governance is implied. Generalized usefulness testing comes before release claims;
personal-data testing can remain deferred. These are open design choices, not
missing implementation checkboxes.

## Supersession and conflicts to reconcile

1. **Scope:** SPEC §3 still lists MCP as deferred, while SPEC §14, the dedicated
   contracts and merged code provide it. This is stale summary prose, not a reason
   to rebuild or undo MCP. query-core's opening branch/release chronology is also
   historical.
2. **Manual organization:** [rulings](../design/rulings.md) declined authoring and
   manual grouping; [projects/works](../design/projects-and-works.md) explicitly
   supersedes project filing restrictions; [review](../design/review.md) later adds
   collections and keeps. Briefs/dossiers and automatic lineage remain unadopted.
3. **Capture:** capture's early layer text and later “as built” differ. Per-request
   spans, inode-change guard and cache-marker exclusions in SPEC §5.3 take priority.
   Its broad historical file count does not prove attribution or current recall.
4. **Current vs selected bytes:** the native current-document ruling and CLI's
   exact-version contract answer different questions. Preserve their labels;
   resolve the intended agent task rather than forcing one meaning onto both.
5. **Structure:** unmerged Thread/Timeline code predates stable reply grouping and
   current organization. Reuse ideas selectively; timestamp equality must not
   become proof of a turn or authorship.
6. **New logical objects:** section access is consistent with native document
   structure but conflicts with query-core's “Not now: outline, content search,
   pagination cursors.” The user goal permits investigation, not implicit acceptance
   of a public API or a general finding/decision schema.

## Experiments versus owner rulings

| Question | Smallest useful experiment | Decision evidence cannot make by itself |
|---|---|---|
| Why are wanted artifacts missed? | Fresh current-main ingest of independent labeled synthetic providers/workspaces; separate syntax, capture, admission and query misses | Whether observations should be searched by default |
| Does more discovery help action? | Hold corpus fixed; compare current named-first search, native-parent context, and one deterministic field-weighting/grouping alternative; measure precision and expansions | First-layer product composition and acceptable omission/noise tradeoff |
| Can R1 be found safely? | Report selection → exact-byte outline → scoped section; duplicate IDs, changed/missing files, repeated headings | Whether findings become persistent objects and who may relate/rule on them |
| Do semantics earn their cost? | Exact-ID, paraphrase and near-topic distractor queries under identical scope; try lexical context first | Opt-in data/model policy; no external model is presently required or authorized by this checkpoint |
| Does capture preserve user state? | Same synthetic library before/reread/migration, compare corrections/reviews/captures and backups | Long-term retention/deletion policy for snapshots and unresolved corrections |
| Does Linux predict Mac? | Actual Swift core/CLI execution with identical portability shims on baseline/prototype | Native FSEvents, APFS/UTType, UI, drag, accessibility and visual acceptance |

## Current evidence, deliberately bounded

- Actual baseline and prototype Swift binaries build in a Swift 6.2.4 Linux
  container, with identical narrow portability boundaries. This is not native Mac
  execution. Native UI, FSEvents and attributed Markdown presentation are excluded.
- Extractor-only smoke: baseline **4/10**, prototype **10/10** asserted cases.
  Some assertions encode proposed range syntax, so this is feasibility evidence,
  not measured delivery recall or user benefit. Relative folder, wildcard literal
  and NUL handling can be evaluated independently of range expansion.
- The first actual Catalog benchmark confirms current-main parent-context search
  and same-byte separate-project scope succeed. A spec plus helpers sharing one
  request yields the desired spec first but **1/5 relevant first results**, exposing
  the difference between correct top result and filtering burden. Body-only `R1`
  and a paraphrase absent from indexed fields miss, as the current contract predicts.
- Full regression, independent held-out and cost results are recorded separately
  when executed; no unexecuted check is counted as passing. No native or release
  gates close here.

## Prototype inventory and recommended convergence sequence

Preserved work: explicit locator syntax prototype; project/outline/section and
paging prototype over Catalog; Linux execution boundary; synthetic task harness;
independently sealed held-out fixtures; primary-source RAG notes. See
[HANDOFF](../../HANDOFF.md) for exact checkpoint state and commands.

Recommended next discussion: first resolve searchable observation scope and what
counts as a logical finding; then compare selective first-layer alternatives on
the same tasks; then choose the progressive agent contract and migration strategy.
Keep defect fixes separable from those choices. Final product/visual rulings remain
with Opus. This report is an input to the next coordinated exploration, not its end.
