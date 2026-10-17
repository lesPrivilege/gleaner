# Could the logical artifact be the first semantic unit?

Yes—as a positioning hypothesis worth testing. A person often wants “the retry policy report”, not a particular path or conversation. A logical object could preserve that referent while agents revise it, rename files or export another format. Project-first navigation can still answer “where am I working?” while the logical object answers “what is this work?” They are different axes.

Main uses path identity and declines inferred lineage, dossiers and generated summaries. The hypothesis extends that model; it does not change the release boundary.

## Compare the three starting points

| Semantic focus | Human benefit | Agent benefit | Cost or blind spot |
|---|---|---|---|
| File-first, current main | Concrete filename, location and selected delivery; easy drag | Exact path/capture handling with few concepts | Renames split history; one overwritten path may contain unrelated work |
| Project-scoped delivery-first | “What did that request produce?”; co-delivered files stay together | Finds purpose and original evidence before choosing a file | Same work across conversations still fragments; a bundle is not necessarily one object |
| Logical-object-first | Follows a work through revisions and representations | Persistent referent for retrieval and handoff plans | Must define object boundaries, establish links, correct mistakes and migrate IDs |

All three permit Project → results → selected object/version. Logical primacy needs a distinguishable identity, not merely a new label for a file row.

## Identity cannot be inferred from one convenient signal

Candidate criterion: a logical object is a continuing unit of intended work. A delivery supplies evidence; a revision fixes a state; a representation is a concrete encoding or component. These meanings remain proposals.

| Counterexample | Why a shortcut fails | Conservative handling |
|---|---|---|
| Same filename, different objects | `report.md` occurs in many projects or roles | Project, request and delivery evidence distinguish candidates |
| Rename/move of the same work | Path identity splits continuity | Explicit source statement or user link can connect it; retain both locators |
| Identical bytes in two roles/projects | A template or attachment is reused | Share byte storage, retain separate contexts/objects unless explicitly linked |
| Many files in one delivery | Report, diagram and patch are related but not interchangeable | Preserve co-delivery first; optional assembly/component relation later |
| Revision across agents | Runtime or session identity changes | Proven relationship can cross agents; actor is provenance, not object ownership |
| PDF and Markdown exports | Similar names may hide different revisions | Representations of one revision only when supported; otherwise separate candidates |
| Same path replaced with unrelated work | Path reuse is not continuity | Preserve delivery history; allow a future explicit split without deleting evidence |
| “v2” name, no evidence | Suffix and proximity are weak hints | Unknown relation remains unknown; do not create a revision edge |
| Two divergent successors | There may be no single final version | Retain both; do not silently impose a linear latest chain |

A hash identifies bytes, not intent. A delivery statement may assert continuity without proving content equivalence. Content similarity can help find candidates, but cannot decide whether two works should share identity.

## Three bounded ways to explore logical primacy

**1. Keep concrete identity and improve navigation.** Expose project, delivery context, co-delivered files and exact versions through the query core. This gives a low-cost control condition. It may satisfy most retrieval without introducing any logical-object state.

**2. Add an optional relationship overlay.** Keep existing path identities; allow an explicit, reversible “continues”, “representation of” or “component of” assertion only when a real task needs it. Store the basis and who asserted it. Display one convenient entry point without collapsing underlying delivery records. An unlinked file remains fully usable.

**3. Give logical objects persistent identity.** New objects receive stable local IDs; projects affiliate them; deliveries refer to them; versions resolve to one or more concrete representations. Initially each existing path can remain an independent seed, with unknown continuity made visible. This creates more durable references, but also a migration and correction obligation. A seed is provisional grouping, not proof that all historical uses of a path are the same work.

Option 2 is a reversible experiment; Opus may choose object primacy first if real tasks demonstrate the need.

## Evidence-backed and user-correctable relationships

An optional link could carry a relation type, endpoints, evidence locator, assertion source, creation time and review state. Distinguish `observed`, `asserted_by_source`, `confirmed_by_user`, and `proposed` rather than inventing numerical confidence. Only relations whose semantics are established should participate in automatic version resolution.

For example, “this file replaces the earlier report” supports a source-attributed replacement claim. It does not prove that every attachment in the reply is another representation of that report. A user can confirm the relationship or reject it without modifying original files, captures or reply excerpts.

Corrections should be separate from re-derived metadata, survive rescans and be undoable. Splitting mistaken objects must preserve existing exact-version references; an old object reference may return a disambiguation set instead of being silently redirected. Permission scopes must not broaden merely because two objects are linked. DataHub's editable metadata aspects offer a concrete separation pattern. [Tagged implementation](https://github.com/datahub-project/datahub/blob/v1.6.0.3/metadata-models/src/main/pegasus/com/linkedin/schema/EditableSchemaMetadata.pdl).

## What richer schemas can and cannot buy

Schemas make valid operations explicit: an exact read requires a selected capture; a project label is not an identifier; an unavailable version has no file to transfer. They improve validation, correction, retrieval filters and auditability. Semantic types such as “report”, “revision”, “representation” and “source assertion” can prevent category errors when their definitions are useful and consistently populated.

The cost is not merely extra columns. Every new type creates classification work, missing values, conflict handling, user correction, indexing rules, compatibility promises and migrations. Rich metadata can become stale while still looking authoritative. Uncertain relationships need a genuine unknown state; type validation cannot establish that a claim is true.

The World Wide Web Consortium (W3C) Data Catalog Vocabulary (DCAT) separates datasets and distributions and models versions; PROV separates entities, activities, agents and qualified provenance relations. These are useful distinctions, not reasons to adopt Resource Description Framework (RDF), a graph database or either complete vocabulary. [DCAT 3](https://www.w3.org/TR/vocab-dcat-3/), [PROV-DM](https://www.w3.org/TR/prov-dm/).

“Schema engineering” is not treated here as one paper or unified method. Three precise bodies of work help: schema matching distinguishes evidence used to suggest correspondences; provenance distinguishes why a result exists from where a value came from; schema evolution treats old queries and data migration as obligations. Their exact works and boundaries are in the [source atlas](03-identity-schema-atlas.md).

## Relating the Courtwork principle without importing its architecture

The supplied principle **Event Log ≠ Matter State ≠ Model Context** highlights a useful separation. In Gleaner, a provider transcript records events; an artifact registry records delivery/capture observations; a bounded retrieval response selects material for a task. None is automatically a complete matter state, and none should replace the other.

Under **Store → Govern → Retrieve → Compile**, Gleaner's analogue could be: preserve observations and bytes → resolve identity, provenance and access → select exact relevant material → assemble a small context packet with references. “Compile” can be deterministic selection and formatting; it need not mean generating a dossier or summary. Governance can initially mean a few enforceable selection rules, not a new governance product.

Reusable mechanics: reference envelopes, exact-byte resolution, bounded ranges, generation-aware paging, source attribution, correction history and schema compatibility. Gleaner-specific meaning: what counts as a delivery, project derivation, delivery-time confidence, filename preservation, snapshot policy and native handoff. Keep those meanings owned by Gleaner. Extract a general library only after a second real consumer proves the shared boundary.

## Tests that should choose among these options

Give humans and agents the same small corpus with all counterexamples above. Ask them to find a named work, select an old state, distinguish exports from revisions, explain one asserted link, correct a mistaken grouping, and hand off exact bytes.

Measure task correctness, wrong-object merges, wrong-version transfers, clarification frequency, correction effort, retrieval bytes and time. Run the file-first control, delivery-first view and optional object overlay. Favor object primacy if it materially improves continuity tasks without adding recurring filing work or hiding uncertainty. Schema completeness is not the success metric.
