# 5. Minimal conceptual model and alternatives

Everything in this part is a research proposal. The goal is to answer “what can I retrieve, why do we think it belongs here, what remains uncertain, and who decided?” A knowledge graph is optional.

## Separate the objects people otherwise conflate

| Concept | Minimal fields / meaning |
|---|---|
| Logical artifact | Catalog ID; domain; identity policy; optional human title. A continuing object under a chosen policy, not automatically a path or content hash |
| Representation | Media type; byte length; digest algorithm/value when known; source version; normalization/encoding if relevant. Exact raw bytes and rendered/normalized text are separate representations |
| Occurrence | A declaration, delivery, revision, export, or observation involving an artifact. Keeps repeated deliveries distinct even if their bytes match |
| Locator | Typed source namespace, resource key, version constraint, optional selector; retrieval capability and current resolution status |
| Evidence unit | Natural source record: message, tool call, tool result, Git commit/tree/blob, snapshot entry, or log segment. Source/version ID, selector, digest/completeness, source permissions and acquisition time |
| Assertion | Subject/predicate/object, assertion kind, supporting and contradicting evidence IDs, assumptions, extractor/rule version, asserted time and claimed event interval |
| Authored decision | Actor, target assertion/representation, purpose, approve/reject/correct/revoke, reason, timestamp, supersedes ID, concurrency revision |

These may be tables with foreign keys, JSON documents, or a small relational core plus object files. An assertion can be stored as a typed row rather than an arbitrary triple.

Example: a reply declares delivery of `report.pdf`; a tool call intends an export from `draft.md`; its result reports success; an immutable blob supplies PDF bytes; an observer independently reads that blob; a reviewer approves a particular digest for external sharing. These are six distinct facts. A single “artifact is verified” flag cannot express them.

## Evidence-strength vocabulary

Use categories **per assertion**, with explicit trust and scope, rather than a total rank for an object:

| Code | Category | Safe statement |
|---|---|---|
| D | Declaration | “This reply named this artifact / claimed this action.” |
| I | Intent | “This tool input requested these changes.” |
| X | Execution report | “This paired result reports success/failure/partial completion under these tool semantics.” |
| O | Observation | “These bytes were read from this source representation at this observation boundary.” |
| R | Conditional reconstruction | “These bytes follow from this complete base and these specified transitions, under listed assumptions.” |
| T | Delivery-bound representation | “This immutable representation was explicitly bound to this delivery/transfer by this evidence.” |
| H | Hypothesis | “This candidate relation/history is plausible or consistent, but not established.” |

Unavailable, denied, conflicted, truncated, unsupported, and not-yet-checked are resolution/coverage outcomes, not evidence strengths. A failed call is strong evidence of a reported failure but weak evidence about the final file state. A byte observation can be exact while its connection to a delivery remains H. Approval is authored authority for a purpose; it does not promote H to an observed event.

For each assertion track independently: source authenticity/integrity; completeness; identity binding; temporal binding; transition determinism; and permission to disclose. Avoid numeric confidence until a labeled evaluation supports calibration. Two excerpts copied from the same tool result are one underlying source, not independent corroboration.

## Natural evidence units and an example address

Prefer provider message/tool IDs plus version-bound record selectors. If a source has no stable ID, use an explicit source-generation identifier and byte range, with a digest over the record bytes. Record line numbers as navigation aids. Keep a digest of the containing source or an immutable segment/prefix when authorized; an append-only file's whole-file hash changes on append.

```json
{
  "evidence_id": "ev:synthetic-42",
  "source": {"kind": "session-log", "namespace": "local-fixture",
             "generation": "log-generation-3", "schema": "fixture-v1"},
  "native_record_id": "tool-result-9",
  "selector": {"kind": "byte-range", "start": 1024, "end": 1180},
  "record_digest": {"algorithm": "sha256", "value": "<digest>"},
  "complete": true,
  "observed_at": "2026-10-17T00:00:00Z",
  "role": "supports-execution-report",
  "visibility_policy_ref": "local-owner"
}
```

This is illustrative, not an adopted schema or URI standard. Validate selectors against the source generation before dereferencing. Redacted and normalized excerpts need their own transformation metadata; their offsets must not masquerade as raw-log offsets. [Web Annotation](https://www.w3.org/TR/annotation-model/) is a useful selector/state precedent, while the exact message/tool addressing scheme remains domain-specific.

## Admission adapters: a boundary worth testing

A Gleaner delivery adapter should answer three separate questions:

1. **Declaration:** Does the user-facing message hand over this target under the domain's versioned admission rule? Produce a decision plus source spans and reason; preserve unresolved candidates separately.
2. **Corroboration:** Which paired tool results, observations, immutable objects or retained snapshots support or contradict specific claims? Tool activity alone does not admit an artifact.
3. **Context:** Which request, cwd, session branch, repository, and surrounding messages explain the declaration? Context does not become evidence of successful generation by proximity.

The adapter output can be `{declarations, evidence, hypotheses, exclusions, coverage_report}`. Domain policy controls what “delivery” means; provider decoding controls record syntax. A failed export named in a final reply can yield an admitted declaration with unavailable bytes and a contradictory execution report. This is more useful than silently deleting the declaration or calling the artifact successfully generated.

Different domains may admit an object by a signed publication record, finalized database job or approved release manifest. Those are examples only: another provider transcript is not a real second domain. Generalize after an actual second workflow tests these boundaries.

## Persistence: three distinct responsibilities

| Store | Contents | Rebuild and deletion behavior |
|---|---|---|
| Derived index | Parsed declarations, normalized fields, search indexes, candidate scores, resolution views | Rebuildable only while source evidence and relevant parser versions survive; extraction changes may supersede assertions |
| Authored ledger | Corrections, identity links/splits, approvals, rejection reasons, retention choices | Not reconstructible from provider logs. Preserve history and explicit revocations; avoid silent overwrite during reindexing |
| Evidence/capture store | Authorized minimal source evidence and byte snapshots, with manifests | A dispensable cache only while authoritative bytes remain retrievable. A sole surviving preservation copy needs explicit retention/deletion controls |

“Derived” describes how a value originated, not whether it remains recoverable. If the provider deletes the original transcript, a retained observation record can be unique evidence. Document that distinction in deletion behavior. The current Gleaner registry is not retroactively assigned these responsibilities by this report.

## Storage alternatives

| Alternative | Suitable when | Cost / failure mode |
|---|---|---|
| SQLite tables + immutable content files + audit table | One local user, bounded catalog, clear typed operations | Must carefully migrate IDs and preserve audit links; recursive joins suffice for modest chains |
| Append-only assertion/decision log + materialized views | Rebuild, correction history and competing interpretations matter | Versioned reducers, ordering and deletion/redaction requirements add complexity |
| Document records with evidence arrays | Small heterogeneous schemas and simple retrieval | Cross-document identity/correction integrity needs explicit validation |
| RDF/PROV or property graph | Multiple domains need interchange and path reasoning | Adds ontology/query/permission complexity; graph structure cannot repair missing evidence |

Start by testing the smallest option. Export selected claims through [PROV-DM](https://www.w3.org/TR/prov-dm/) if interoperability is useful; do not equate storing a graph with proving causality. A reconstruction activity can have its own provenance and assumptions even when the historical derivation remains hypothetical.
