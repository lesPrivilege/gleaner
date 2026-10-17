# Project knowledge and editorial organization

Exploratory reference at [`79d724d1228a4b748572958dcbdd22aa6b7da142`](https://github.com/lesPrivilege/gleaner/tree/79d724d1228a4b748572958dcbdd22aa6b7da142). Project is the primary affiliation; these alternatives concern how a person reads its delivered work. They do not mandate more screens, a knowledge platform or a new canonical schema. Current-code capabilities and shared validation limits are recorded in the [source review](design-review-evidence.md).

The distinction is between **what was delivered**, **what a source says**, and **how the person wants to understand it**. A useful outline can organize evidence without becoming the project's authoritative plan. No summary, classifier or graph is necessary for the minimal reduction.

## Three distinct editorial directions

| Direction | Reader's question | Persistent structure | Main cost |
|---|---|---|---|
| **Project delivery shelf** | What did the agents deliver? | Existing project-scoped outputs; contribution context revealed with selection | The reader reconstructs reasoning across reports |
| **Project work brief** | What evidence bears on the project's purposes? | Small editable questions linking contributions and exact outputs | Editorial upkeep and a risk of resembling a project plan |
| **Bounded project topic dossiers** | What have deliveries said about this concern? | Chosen topics with source-linked passages and representations | Classification effort and a risk of unsupported synthesis |

These are alternatives, not three compulsory tabs. The panel's [composition options](control-panel-explorations.md) address a different axis: list/detail reduction, handover grouping and a personal selection. For example, a shelf can use handover groups; a brief can use a compact list beneath each question. Combining them should reduce a demonstrated retrieval burden rather than accumulate navigation systems.

## A four-week synthetic project

All names, dates, measurements, excerpts and paths here are invented. CedarSearch is a local document-search application with contributions from several agents and conversations, a main checkout, and ranking/release worktrees. Their affiliation does not depend on where the agent stores a worktree. The sample is deliberately human-labeled; it makes no claim about provisional extraction accuracy.

| Delivery | Original outputs in reply order | Evidence that matters |
|---|---|---|
| Sep 7 | `baseline.md`; `latency.svg`; `benchmark.csv` | Report structure: Method, Results, Limitations. It reports 180 ms p95 on a stated 10,000-document corpus. |
| Sep 10 | `option-a.md`; `ranker-a.swift` | Both report and source file are explicitly offered as outputs. |
| Sep 12 | `option-b.md`; `ranker-b.swift` | Competing implementation with a different benchmark corpus; a sibling alternative, not automatically A's next version. |
| Sep 16 | `comparison.html`; `quality-v-latency.svg` | Comparison uses a common benchmark and links A/B. An embedded `error-breakdown.svg` is not independently delivered. |
| Sep 19 | `adr-004-ranking.md` | Source states A is accepted for the first release, with multilingual evaluation deferred. |
| Sep 23 | `comparison.html` again | New delivered bytes add a multilingual limitation; an older saved copy preserves Sep 16. |
| Sep 26 | `release-notes.md`; `CedarSearch-0.4.0-rc1.dmg` | Reply calls installer signed and ready. Later the worktree disappears; only notes have saved bytes. |
| Oct 2 | `follow-up.md`; `multilingual.svg` | Questions A's suitability without explicitly superseding the ADR. |

The sample has 15 delivery mentions across 14 distinct artifact paths. Those counts describe the sample, not project completeness. The two comparison deliveries remain distinguishable. Linked dependencies do not become admitted artifacts through linkage, a reported measurement is not independently verified, and a hash does not establish which code produced a figure. Editorial proximity between release notes and an installer does not prove release readiness.

## A. Project delivery shelf

The smallest form is the existing list/detail composition with project context established once. The reader sees recognizable outputs and reveals their contributing deliveries. A separate delivery-group screen is unnecessary.

```text
CedarSearch — delivered work
  Oct 2: Multilingual follow-up — contribution and outputs
  Sep 26: Release candidate — notes; installer unavailable
  Earlier deliveries
Optional personal selection: September review
  comparison.html [Sep 23]; quality-v-latency.svg; adr-004-ranking.md
```

Recency helps return after a week; search relevance helps retrieval; manual order helps a particular review. A frozen selection can retain exact versions, while a dynamic saved search includes new matches. Name that difference. Neither a saved view nor a position pin preserves file bytes.

Keep project, purpose, recognizable output, selected-version basis and availability qualification persistent. Reveal excerpts, provider/session, paths, other occurrences and personal notes in context. Put a report's own Contents inside its detail, not into the permanent project tree.

Minimum: existing output/delivery selection, reliable or explicitly unresolved affiliation, and retained navigation state. Personal sets and saved filters are optional. A curated set can hide new work; a small indication of new matches outside the selection is an option, rather than silently updating a frozen set.

[Zotero collections](https://www.zotero.org/support/collections_and_tags) demonstrate non-exclusive membership without item duplication and distinguish saved searches that update from criteria. The transferable point is membership semantics, not a requirement for nested folders or Zotero's workflow.

## B. Project work brief

A small, human-maintained question outline organizes received evidence. Contributions from several agents meet under one purpose. It is an editorial arrangement, not automatic task tracking. A person can author it or start from a delivered brief's headings; importing headings retains source attribution until explicitly made into a separate personal arrangement.

```text
CedarSearch — My review outline
  What behavior are we evaluating?
    baseline.md → Method; benchmark.csv
  Which ranking approach fits the first release?
    comparison.html [Sep 23]; options A and B with their source files
    adr-004-ranking.md — source says Accepted
  What still needs judgment?
    follow-up.md → Multilingual limitation
    My question: Does this invalidate the release choice?
  What can I hand off?
    release-notes.md; installer unavailable
```

Purpose-to-evidence order helps resumption; urgency order can help a review meeting. Putting the comparison before underlying reports changes reading order, not delivery chronology or dependency semantics. A section says “No linked delivery in this outline” when empty, not that the work never happened.

Keep the chosen outline's personal status, questions, linked outputs and availability visible. Reveal source headings, exact passages, earlier deliveries and grouping rationale under the relevant question. No completion percentage or green approval mark is implied by a populated section.

Minimum additional capability: editable local outline, links to artifacts or exact deliveries, and personal order. Passage anchors or heading import can follow only if helpful. Maintenance is the cost; separate small outlines may be clearer than an expanding master plan.

[Diátaxis](https://diataxis.fr/) organizes documentation around reader needs. Its lesson here is to ask what someone needs from the output, without importing its categories as Gleaner's taxonomy. [Nygard's ADR practice](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) supports inspectable context and supersession history. Gleaner can show “ADR 004 states Accepted” without claiming authority over that decision.

## C. Bounded project topic dossiers

A person selects a recurring concern, such as Search quality. A dossier gathers chosen outputs and passages, with optional orientation notes. Explicit cross-project references retain their originating project. The scope remains selected evidence, not an autonomous wiki.

```text
Search quality — CedarSearch
  My orientation note — based on listed sources through Oct 2
  Evidence: comparison [Sep 23] → limitation; follow-up → recommendation
  Earlier alternatives: option-a.md; option-b.md
  Related decision: ADR 004, first-release scope
  References with their citing artifact/version
```

Chronology shows development; relevance supports a particular question; a personal note can help orientation. Grouping evidence into “supporting” and “challenging” is a stronger interpretation that needs a source assertion or personal judgment, not similarity alone.

Keep project, topic, actual source entries and note origin/coverage visible. Reveal aliases, related topics, older material and proposed membership. A small related-topic list can suffice; no graph is required. Overlap is legitimate: topics need not partition every artifact, and similar labels in different projects need not mean the same thing.

Minimum additional capability: user-chosen labels and membership, source links and optional local notes. Passage targeting and aliases are conditional. Automatic topic creation is not needed. The principal risk is confident synthesis of incompatible evidence.

[SKOS](https://www.w3.org/TR/skos-primer/) distinguishes preferred/alternative labels, broader/narrower relations and associative relations. That vocabulary helps avoid treating latency as synonymous with search quality or “related” as “derived from.” It does not require RDF or a universal ontology.

## Preserve the origin of structure and order

| Structure | Legitimate basis | Boundary |
|---|---|---|
| Delivery evidence | Recorded user-facing reply and source position | Does not prove correctness or acceptance |
| Source-authored structure | Headings, links, stated statuses in identified content | Does not mean Gleaner agrees |
| Mechanical extraction | Reproducible headings/link extraction | Does not form a complete project ontology |
| Proposed interpretation | Attributed rule/model suggestion | Is not original source structure |
| Personal arrangement | Explicit grouping, order or annotation | Does not change source records or imply shared approval |

Decision, question, reference, variant and deliverable can be roles within an arrangement rather than exclusive object types. A report can contain several roles without requiring several top-level sections.

Keep original reply order, delivery chronology, source-document order, retrieval order and personal reading order distinguishable. A stable tie-break aids usability but does not prove temporal order across independent sessions. The current extractor retains occurrence evidence/first-mention order; the library projection groups by path and sorts by most recent delivery. Preserving original multi-output order is a projection question, not an unfixed claim that all occurrences are lost. [Extraction](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/MentionExtractor.swift) · [registry projection](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Registry.swift#L79-L118)

Emphasis needs a basis: a personal “read first,” a new recorded delivery or unavailable selected bytes. It must not silently mean important, complete, approved or preserved. Version-bound personal review could be explored later; it is not a present v0.1 workflow. Collapsed families should leave alternatives discoverable rather than crowning the newest as winner.

## Outlines and optional summaries

Source headings are the lowest-assumption content outline. Preserve text/order and the representation they came from. A personal outline can reorder or alias them without rewriting that source structure. Unsupported formats can remain recognizable entries with appropriate preview/Open behavior.

No summary is needed for the minimum shelf. If a work brief or dossier later benefits from one:

1. Select exact available representations or delivery excerpts. State when only excerpts were read; never imply a lost file was inspected.
2. Identify extractive text, a human note or a generated proposal. Retain source versions and edit/generation time.
3. Link material statements to support and preserve qualifications such as corpus, date and scope. Citation establishes origin, not truth.
4. Let the person correct wording/membership and reject suggestions without changing evidence. Rejected suggestions should not return unchanged on refresh.
5. When relevant inputs change, propose a diff and retain human edits and the prior basis until adopted. Show evidence coverage separately from the note's update date; unrelated new work need not invalidate a frozen review set.

A bounded note may say that the September ADR chooses A for the first release while the October report questions multilingual behavior without explicitly replacing that decision. It must not condense this into an assertion that A is approved and multilingual work complete.

[Web Annotation](https://www.w3.org/TR/annotation-model/) separates note bodies from targets and supports selectors/resource state. A small equivalent might link a capture to a heading or quoted passage with context; broken/ambiguous anchors should not silently attach to new text. [PROV-DM](https://www.w3.org/TR/prov-dm/) supplies the distinction between attribution, derivation and responsibility, including the basis of derived material itself. Neither source requires a graph UI.

All three minimum models work without an LLM. File-content synthesis would require a deliberately scoped reading capability. Current [SPEC §14](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/SPEC.md#L218-L247) permits optional network reasoning over minimal redacted excerpts/metadata, not whole file contents; remote content summarization cannot be assumed to fit that contract.

## Common identity and naming boundaries

The [reference notes](control-panel-reference-notes.md#2-project-identity-affiliation-and-navigation) compare scoped human assignments, confirmed bindings and repository/worktree evidence. Another optional source is a user-controlled stable project declaration, imported read-only; it cannot be required for existing or non-Git work. Git metadata establishes linked-checkout membership, not logical project identity. [Git worktrees](https://git-scm.com/docs/git-worktree) · [repository layout](https://git-scm.com/docs/gitrepository-layout)

Keep one-delivery corrections distinct from future defaults or date-range assignments. Explicitly shared projects/repositories can need multiple affiliations; provider containers, ancestor names and matching remotes cannot resolve them alone. A foreign-project reference is not reassignment. Detailed binding evidence belongs behind a concise project label or unresolved state.

For cross-path revisions, distinguish an evidence-backed revision link, a human-confirmed logical deliverable and a presentation-only family. The latter deliberately asserts no lineage. Related histories should remain separable without deleting deliveries or saved bytes. These alternatives and the filename/title/alias/export distinctions are elaborated in the [composition guide](control-panel-explorations.md#names-have-different-jobs) and [instance notes](control-panel-reference-notes.md#10-one-deliverable-revised-across-agents-and-conversations); naming must not create identity silently.

## Walkthroughs and failure checks

- **Older comparison:** enter the Sep 16 result, inspect why those bytes are selected, return to the same query/position, then enter the project without switching to Sep 23.
- **Question outline:** enter Which ranking approach, inspect option B, go back to the same section/expansion and switch to A. Neither action selects a winner.
- **Handoff and resume:** retain the selected release version when bytes are unavailable; offer explicit alternatives. Return to the same project position. Opening or beginning a drag does not establish completed review or successful transfer.

| Failure to exercise | Misleading result to avoid |
|---|---|
| Different corpora or scopes | An unqualified A-versus-B ranking |
| Backfill or absent source | A summary claims to describe delivered bytes it never had |
| Later disagreement / experiment | Automatic supersession or newest-as-authoritative |
| Collapsed variants / reused path | Alternatives disappear or unrelated work inherits one history |
| Embedded references | Recursive crawling admits undelivered dependencies |
| Empty section | No linked evidence is mistaken for no work performed |
| Wrong affiliation / alias collision | Agent-owned storage or a polished name fabricates project identity or approval |
| Human edits followed by refresh | Nuance and prior source basis are overwritten |
| Matches within collapsed groups | Search loses relevant originals or rewrites personal order |
| Position pin | Prominence is mistaken for preserved bytes |

The minimum reduction can stand alone. Richer editorial state is justified only by a demonstrated re-entry or retrieval task. The amount of state, whether an outline begins with a person or a source document, and whether summaries add value beyond excerpts/headings remain choices for Opus. The common requirement is a direct route to original delivery evidence and the explicitly selected file representation.
