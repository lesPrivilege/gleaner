# Evidence contract and lifecycle

## Facts the fixture must distinguish

Use separate records for logical object, observed version, delivery occurrence, source locator, content digest, evidence span, capture, authored annotation and approval event. These are research distinctions, not a prescribed product schema. A digest identifies measured bytes under an algorithm; it does not identify project, logical work, provenance or authorization. Two projects can independently contain identical bytes. A transcode can preserve useful content while changing bytes, and a renamed file can retain bytes without proving continuity.

Record a relationship's basis: explicit source statement, observed transform/move, owner-authored link, or uncertain candidate. Similar titles, dates or hashes can produce candidates, never silent identity merges. Bundle membership and independent member references coexist: a diagram can be a report's member and a separately cited artifact. Neither relation makes the whole bundle available.

For every evidence-bearing fact retain source ID, source digest, snapshot/epoch, record ID plus span/byte range, extraction version/config, and an observation qualifier. Where present, retain actor, target object/version, event time, observation time, operation, result and scope. Distinguish asserted, requested, attempted, observed-success, observed-failure and unknown. A tool call without a corresponding result is an attempt with unknown outcome. A result saying a command exited successfully may establish that observation but not every unstated postcondition; byte-level questions need actual bytes or trusted digests from the specified observer.

An approval needs the approving actor's recorded authority, exact target/version or explicit scope, operation/purpose, effective time and any revocation/supersession. In synthetic worlds the owner/authority policy is supplied to both arms. In real material an independent owner may have to establish authority or intent. The label is then recorded with that basis; it is not retroactively attributed to a log that never said it.

An irreplaceable snapshot is new historical evidence. A later live file, mtime heuristic, logged write input or digest cannot recreate missing earlier bytes. A logged command containing text does not prove that text reached disk. A missing log, truncated tool output or inaccessible source yields an observable-information limit; even an annotator who knows the hidden world state cannot require the agent to guess it.

This maps to the entity/activity/agent and derivation distinctions in [W3C PROV-DM](https://www.w3.org/TR/2013/REC-prov-dm-20130430/). Using those concepts does not validate a particular record or require RDF. [ReproZip's developer guide](https://docs.reprozip.org/en/stable/developerguide.html) usefully distinguishes the captured trace from configuration augmented by later machine inspection; adopt that caution about observation times rather than treating a tool-input transcript as complete provenance.

## Three lifecycles

| Class | Examples | Rebuild and deletion semantics to test |
|---|---|---|
| Derived, reproducible under fixed inputs | Search postings, catalog fields, deterministic excerpts | Regenerate only from retained source snapshots plus pinned extraction/config/normalization; report missing inputs |
| Authored, not derivable from raw logs | Accepted alias, cross-listing, exclusion, owner annotation | Preserve independently; retain target and scope; unmatched targets remain unresolved; never infer replacement targets from similarity |
| Historical observation/payload | Pre-overwrite capture, original approval record, observed hash/time, lost-item evidence | Preserve as evidence according to policy; rebuilding an index cannot regenerate destroyed history |

Original files remain with source systems. The benchmark uses read-only frozen copies or replay fixtures for repeatability; these are measurement inputs, not a proposal to relocate originals. Captured history is a distinct preserved record. Refreshing a cache, rebuilding an index, removing a catalog item, deleting a snapshot and deleting sensitive evidence are different operations. A retention policy must explicitly handle dependencies; a tombstone must not secretly preserve content a deletion policy removes.

Retain evidence that a lost item was referenced, last observed facts, known search scope and unresolved candidate locations. A lost-work record does not claim that the lost payload is recoverable. Re-observation can update availability without rewriting earlier observation facts. An unverified Git candidate stays a candidate until the required comparison or explicit lineage evidence is available. A hash match verifies bytes under the comparison conditions; project/approval identities remain separate.

The pinned [Registry implementation](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Registry.swift) separately stores deliveries and captures, and its removal path deletes capture rows for deliveries no longer admitted while leaving saved payload copies. This source reading motivates testing evidence reachability after re-extraction. It is not an executed bug finding or a requested fix. The future study must distinguish payload retention from retention of the metadata needed to locate and interpret it.

## Freeze and rebuild protocol

Create a source manifest before extraction: relative locator, origin/source-system ID, type/encoding, byte size, SHA-256, capture method, event/observation timestamps where known, access status and known omissions. Include logs, source payloads, authored state, approval ledgers and snapshots as separate inputs. Missing inputs remain explicit entries; do not fill them from a live account during a trial.

Pin adapter source revision, dependency/tool versions, extraction flags, admission rules, timezone, locale, Unicode normalization, line-ending policy, sort/tie-breaking rules, redaction configuration and truncation limits. Keep raw byte hashes alongside any canonical text hashes. Unicode normalization must not silently coalesce distinct filesystem names. Every canonicalization rule belongs in a versioned specification.

Compute an input identity from sorted source-manifest content, extractor revision, configuration and normalization version. Rebuild twice from identical inputs in fresh scratch directories, randomizing source enumeration order. Compare canonical logical output and a separately reported physical serialization hash. Exclude only preregistered volatile fields such as build timestamps from canonical comparison; retain them in audit records. If an LLM extractor is later tested, save exact model/prompt/version and run multiple builds as a separate nondeterministic condition, including its costs.

Then perturb one factor at a time: source bytes, source location, extraction version, normalization or configuration. Report source drift separately from extractor nondeterminism. The immutable core corpus never changes mid-episode; stale-pointer cases use named frozen epochs, and race cases use a deterministic replay schedule. Both arms receive the same snapshot boundary and access rules.

For lifecycle checks, delete only the probe's derived directory and rebuild. Verify authored annotations, capture hashes, capture-to-delivery links, lost-item evidence and unresolved candidates remain reachable. Test an adapter rule change that no longer admits a prior delivery: the policy for preserving historical evidence must be stated and measured. Do not equate byte survival in an orphaned content store with usable historical preservation.

## Bibliographic metaphors

Catalog, lost-work record, cross-listing and analytic entry are useful prompts: separate description from possession, preserve references to missing material, allow multiple memberships, and describe independently referenced parts. This protocol makes no historical claim about those practices and does not establish that a library metaphor fits agent workflows. Test these distinctions by behavior and evidence. Historical verification, if desired later, is its own research question.
