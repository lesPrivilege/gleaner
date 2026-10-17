# Evidence, personal organization and output lifecycle

These notes supply the less visible distinctions behind the [control-panel alternatives](control-panel-explorations.md). They do not prescribe new screens or one combined schema. The baseline is `79d724d1228a4b748572958dcbdd22aa6b7da142`; current capabilities and validation limits are recorded once in the [source review](design-review-evidence.md). All examples are synthetic.

## Keep the immediate decision small

Ordinary selection needs project, a useful recognition cue, the chosen instance and its availability. Evidence disclosure can answer the deeper questions without presenting a transcript:

| Question | Useful retained evidence | Limit on the claim |
|---|---|---|
| Who delivered this? | Provider and user-facing reply; agent/model name if recorded | Delivery attribution is not proof of authorship |
| For which request? | Bounded relevant request passage attached to that reply | Requested work is not proof of completed work |
| What was offered? | Original target, reply passage and source occurrence | Mentioning an output does not establish its quality or completeness |
| When was it observed? | Reply, byte-check and saved-copy times | A later observation is not historical simultaneity |
| Which bytes remain? | Source or saved/staged bytes with a check result | Thumbnail availability does not mean the original is recoverable |
| What does equality establish? | Digest of the measured payload and its observation context | Equal bytes do not imply equal projects, logical work or approval |

Current capture classification uses a time window and file mtime. Verified staging strengthens the transfer's byte identity, but does not prove the bytes existed at the precise original reply time. Keep “first seen later” legible wherever those bytes are selected. OpenTelemetry's separate event and observation timestamps provide a transferable distinction, not a new telemetry requirement. [Indexer:46–50, 135–154](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Indexer.swift#L46-L154) · [OpenTelemetry timestamps](https://opentelemetry.io/docs/specs/otel/logs/data-model/#field-observedtimestamp)

Prefer source excerpts and deterministic counts before generated prose. “Two outputs named; one saved copy available” can be supported by records. “Request completed” needs different evidence. Indicate truncation or redaction and keep occurrences attached; Web Annotation's quote and position selectors illustrate why a passage's context matters when a document changes. [Web Annotation selectors](https://www.w3.org/TR/annotation-model/#selectors)

If redaction is used, derive indexed snippets from retained redacted text. Pattern matching cannot guarantee that project names or business context are harmless. Redacting evidence does not sanitize saved artifact bytes. An evidence export should contain deliberately selected passages; optional summaries follow the [editorial chapter's source and refresh rules](project-knowledge-explorations.md).

## Search explanation without more infrastructure

The original single-term older-delivery bug is fixed. A remaining case spans deliveries: D1 says “retry policy,” D2 says “board cut,” and `retry board` can match the combined history while selecting D2. The exact prototype functions were exercised; corresponding native behavior is a source reading, not an executed native test. [Search evidence](design-review-evidence.md#2-search-still-needs-a-clear-evidence-scope)

Two alternatives stay open: require ordinary terms to match within a single delivery's fields, or retain history-wide matching with “Matches across 2 deliveries” and the separate passages. Neither should invent a combined request. Query changes can preserve a visibly explicit selection or deliberately reset it; the result, preview and takeaway must explain which meaning applies.

Current SQLite plus in-memory matching may be sufficient. Structured queries could add project/availability scopes. Only if lexical retrieval or scale warrants it, a per-occurrence FTS5 projection could support ranking and snippets while retaining match IDs through grouping. FTS5 external-content indexes require synchronization; Datasette supplies an example of inspectable fielded SQLite search. These are optional mechanisms, not dependencies selected by this design round. [SQLite FTS5](https://www.sqlite.org/fts5.html) · [Datasette full-text search](https://docs.datasette.io/en/stable/full_text_search.html)

## Personal organization should survive a rescan

An **assignment override** changes where the person files an output; an **additional project link** also shows it elsewhere. Both retain observed source context. Choose either only if needed. “Assign here” and “Also link here” have different consequences when both exist.

The minimum persistent record needs a target, chosen project, relationship/scope and enough previous state for undo. It can live in the existing database while remaining separate from disposable search views. Current delivery IDs derive from log path, first evidence line and artifact path; moved logs or changed anchors can produce new keys. Retain a local target or reconcile old/new keys explicitly. An unmatched alias or assignment should remain unresolved, not disappear or move to a similar title/hash. [Indexer:26–30](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Indexer.swift#L26-L30)

**Before → edit → rescan → reset:** D1 is suggested as Atlas, with saved bytes H1 from an external worktree. The person files D1 in Launch kit and names it “Retry demo.” A saved view selects Launch kit videos with saved copies. Rescan changes provider metadata, but D1's filing, alias and H1 remain. If source identity becomes ambiguous, its existing arrangement needs attention rather than being silently reassigned. Restoring automatic affiliation for D1 previews Atlas or unresolved; it removes only that override. The alias and view definition remain, although the view's membership may change. Undo restores the filing.

New evidence can challenge an automatic suggestion without defeating the person's accepted arrangement. A correction for D1 does not automatically capture D2. Broader future mappings need explicit scope. Version bookmarks remain tied to the chosen instance; pinning position and saving bytes remain different operations.

| Management meaning | Scope and consequence to make clear |
|---|---|
| Reset a view | Restore chosen sort/group/density; leave affiliation and files alone |
| Restore affiliation or reset organization | Enumerate selected assignments/links and any included aliases or views; retain source observations and bytes |
| Recompute derived index | Refresh reconstructible evidence/search fields while preserving corrections, exclusions and captures; missing sources limit reconstruction |
| Clear expendable cache | Identify preview/transient staging data and space; avoid active handoff and distinguish any sole accessible transient bytes from preserved captures |
| Delete preserved captures | Identify exact saved contents and affected deliveries; a version can become unavailable if no other accessible copy is established |

These are distinct semantics, not five permanent buttons. Current registry data includes retained delivery/capture evidence and is not wholly disposable cache. A known hash cannot recreate a deleted payload. Privacy deletion must address dependent snippets and summaries; an undo/audit record must not secretly retain text that the chosen deletion policy removes.

## Logical work, historical states and physical copies

The [identity alternatives](control-panel-reference-notes.md#10-one-deliverable-revised-across-agents-and-conversations) compare evidence-linked outputs, logical deliverables with instances and personal groups. Library of Congress BIBFRAME provides a mature precedent for asking separately about work, embodiment and individual copy; its cataloging structure need not be adopted. [BIBFRAME model](https://www.loc.gov/bibframe/docs/bibframe2-model.html)

Consider A, a report; B, one agent's revision; C, another agent's alternative from A; D, a stated reconciliation; and E, D's PDF export. B/C are not a linear sequence merely because one is newer. D has two predecessors only with supporting evidence or confirmation. E has its own bytes and may be a rendition rather than a later revision. Repeating B at another path adds a location or delivery context, not automatically another logical revision.

| Lifecycle case | Distinction to retain | Compact human consequence |
|---|---|---|
| Same source event re-imported versus new reply | Duplicate indexing versus another delivery | Avoid duplicate records while retaining actual redelivery context |
| A → B → A | Three historical states, two byte contents | Return to earlier content without erasing the intervening work |
| Old path reused or copy renamed | Locator history versus identity claim | Relink only with an adequate basis |
| Equal bytes in two projects | Storage equality versus human purpose | Preserve each project/request context |
| Missing before first observation | Delivery evidence without known bytes | Delivered contents remain unknown |
| Git recovery candidate | Candidate contents versus a recorded delivered digest | State uncertainty until a relevant comparison establishes more |
| Only a thumbnail survives | Derived preview versus full payload | Permit recognition without implying recoverability |
| Parallel platform builds | Variants versus successive versions | Choose arm64/x86_64 explicitly when relevant |

Current code already recognizes rollback and saved-copy availability. These are semantics to retain as presentation changes, not a new defect list. Four deliveries can describe three meaningful historical states with only two byte contents; no permanent edition object is needed unless that distinction earns its place.

## Optional assemblies are distinct from co-delivery groups

“Report + CSV + figures” may be one useful assembly even across directories. A reply that mentions three files establishes co-delivery, not necessarily package membership or completeness. A minimal optional assembly records accepted members/roles and selected states; an expandable “Includes…” can expose it without another top-level section. Its benefit is coherent review/takeaway; its cost is membership maintenance and partial-availability handling.

Keep **semantic extent** separate from **preservation inventory**. An intended report/data assembly may have only the report saved. Member names, kinds, digests and relevant metadata describe what was actually retained; coherence across a changing directory may be unknown. The selected missing CSV must remain visible before full-package takeaway. RO-Crate illustrates descriptive collections, while BagIt distinguishes manifest completeness from checksum validity. Neither requires adopting those formats. [RO-Crate structure](https://www.researchobject.org/ro-crate/specification/1.1/structure.html) · [BagIt, RFC 8493](https://www.rfc-editor.org/rfc/rfc8493)

A ZIP digest and an expanded-tree digest answer different equality questions. A usable HTML preview does not prove all dependencies are present. Renaming internal members for prettier export can break references; preserving members and naming an outer package may be safer where packaging is supported. Current folders remain live and unversioned, not historical assemblies.

A remote URL is a changing locator; a screenshot is a representation, not the preserved application. Memento's original-resource/archived-representation distinction is useful if remote outputs are ever added; ordinary remote URLs are outside current extraction. Release names likewise differ from exact platform payloads. OCI's image index illustrates explicit platform alternatives without prescribing container packaging. [Memento, RFC 7089](https://www.rfc-editor.org/rfc/rfc7089) · [OCI image index v1.1.1](https://github.com/opencontainers/image-spec/blob/v1.1.1/image-index.md)

Naming remains a presentation choice: original filename, continuing-work title, optional alias and context supplied by the current view. DCMI distinguishes titles and alternative names while leaving their application-specific use open. Alias edits do not rename originals; exported-copy naming is a separate action. These roles and a same-name-file example are developed in the [composition chapter](control-panel-explorations.md#names-have-different-jobs). [DCMI terms](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/)

The implementation implication is conditional: retain only the accepted organization that cannot be reconstructed, derive displays where possible, and keep the exact selected file usable before every logical relationship is resolved. No agent needs a new submission protocol, and no comprehensive schema is ratified here.
