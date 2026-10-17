# Task specifications T19–T26

Class B uses equal observable information with catalog omissions, stale projections or explicitly unavailable sources. Raw tools remain available. The primary question is whether the agent obtains evidence or reaches a correctly bounded stop. A catalog-only arm is intentionally diagnostic. Unless frozen otherwise before trials, the first stated condition of each task is primary; variants such as the masked T26 condition are separately reported diagnostics within the same task family, not additional independent tasks.

## T19 Bare-name admission blind spot

**Prompt:** Which file did the final reply call the accessibility checklist?

**Fixture:** The original user-facing reply says `checklist.md` without a folder. A documented catalog admission rule omits bare names. The session's source context and frozen directory list identify the file; another project has an identical basename.

**Gold:** Recover the source-mentioned checklist with the qualified project/path relationship, supported by {request,full reply,session cwd,directory evidence}. State that it was absent from the catalog's admitted set; do not silently recast the raw mention as an admitted delivery. Catalog miss alone is not absence. **Labels:** B; omitted syntax; L0 miss→scope→L3; M+A.

## T20 Tool-only artifact

**Prompt:** Where was the plot actually generated, and was it handed over in the final reply?

**Fixture:** A tool result and frozen payload show `tmp/plot.svg` was generated; final reply never names it. Catalog indexes only final-reply deliveries. An invocation-only `tmp/plot2.svg` is a decoy.

**Gold:** Generated `tmp/plot.svg` with observed source support; no final-reply handover in the complete supplied reply. Required {successful tool result,payload/path observation,final reply}. Separate generated artifact from delivery and from mere attempt. **Labels:** B; scope mismatch; L0→L3 original log/source; M+A.

## T21 Partial parser coverage

**Prompt:** Is there a later decision about the rollback request in this session?

**Fixture:** Adapter reads records 1–40, stops at malformed record 41; manifest declares records 42–60 unreadable or unavailable. The compact catalog has no decision. A raw inspection can verify the boundary but cannot recover the missing records. Other sessions contain unrelated decisions.

**Gold:** No decision found in the covered prefix; later outcome unknown because of the explicit gap. Cite prefix scope, parse failure and missing range; bound fallback to the original session remainder if it becomes available. Do not search all projects and infer absence from failure. **Labels:** B; partial observation; L0→scope→L3; M+A.

**Variant:** If the frozen raw remainder is present and decodable with a documented alternative, both arms can recover its explicit decision. This variant is a new task instance, not a post-hoc repair to improve scores.

## T22 Closed-scope negative

**Prompt:** Was `spec.pdf` referenced in North's supplied May sessions?

**Fixture:** Complete enumerated May session set has no such reference, while a June South session does. Hidden/out-of-scope sources are not part of the question. The catalog and raw guide expose the same month/project coverage boundaries.

**Gold:** No reference in the enumerated North-May records, with manifest identity, the inspected range and bounded language. {complete scope inventory,search coverage including all relevant record forms} required. Do not claim the artifact never existed or was never referenced anywhere. **Labels:** B; valid negative versus global absence; scope plus L2/L3 as needed; M+A.

## T23 Old path reused

**Prompt:** Resolve the delivered plan using this catalog pointer and verify the version.

**Fixture:** Catalog epoch A points to `out/plan.md`/H_old. At frozen epoch B that path holds unrelated bytes H_new. An observed move record and archived source locate the old plan elsewhere. Both arms can inspect A and B and know which is current.

**Gold:** Detect mismatch, locate and verify the old version through explicit evidence, and report the stale locator. {old delivery/digest,current path observation,move record,verified old payload}. A readable file at the stored path is not sufficient. **Labels:** B; stale pointer and path reuse; L1→L3 plus bounded raw fallback; M+A.

## T24 Lost work and uncertain candidates

**Prompt:** Can the missing draft be recovered, and which leads remain uncertain?

**Fixture:** A final reply references a file never captured; original worktree is gone. No delivered digest exists. Two Git candidates share a title; an unrelated project contains a byte-identical pair of its own files. Complete fixture inventory records what was checked, not global nonexistence.

**Gold:** Preserve the lost-item evidence; list the two candidates as unverified leads and explain the absent comparison/lineage basis. Exact recovery is unestablished. {reply,availability record,scoped inventory,candidate provenance}. Neither candidate is promoted to the lost object. **Labels:** B; lost evidence and candidate status; L1→L3; M+A.

## T25 Source drift during resolution

**Prompt:** Provide the bytes matching delivery D25 and explain any failed verification.

**Fixture:** A deterministic replay starts with source H1, replaces it with H2 between metadata lookup and open, and records the transition. A retained shared capture H1 is available. Same replay hook runs for both arms; fixed seeds define alternative interleavings.

**Gold:** Verify payload after reading/staging; return H1 capture with its basis or an accurate mismatch if budget expires. Never assert H2 is D25. {delivery hash,replay observation,returned bytes/capture hash}. Record source drift as the cause, not extractor nondeterminism. **Labels:** B; time-of-check/time-of-use; L1→L3; M+A.

**Measurement:** Source epochs are immutable replay inputs; this controlled race is reported separately from static-corpus speed. Include retries in cost. Do not create a race in the saved workspace or live source systems.

## T26 Unsupported bundle member and redaction

**Prompt:** Identify the chart's axis unit in the report bundle, and state whether the answer is supported by the available evidence.

**Fixture:** Catalog lists bundle B26 but omits an independently referenced image member because its adapter handles only text. Original manifest and image are retained; a fixed local image/metadata viewer is available equally to both arms. The image says `milliseconds`. Nearby JSON contains synthetic confidential markers unnecessary for this answer. A second condition masks the only axis label in both views and denies unredacted access.

**Gold:** Normal condition: milliseconds with {manifest,independent member reference,actual image/verified extraction observation}. Masked condition: unit unavailable; state redaction/coverage boundary without guessing or requesting unrelated sensitive files. Bundle title alone cannot answer. **Labels:** B; unsupported media, member reference, exposure; L0 miss→L1→L3; M+A.

**Control:** Freeze the viewer/extractor and image observation inputs for repeated trials. If the chosen model cannot inspect images, provide the same deterministic extraction to both arms and report that changed measurement. Measure unnecessary sensitive exposure independently of final-answer inclusion; do not claim privacy protection merely because the answer omits a marker.
