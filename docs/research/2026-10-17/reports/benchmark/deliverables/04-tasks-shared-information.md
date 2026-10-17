# Task specifications T01–T12

Taxonomy: **E** means the requested facts are observable by both raw and catalog arms; **S** manipulates recorded-state availability; **B** probes an explicit catalog blind spot or scope limit. E tasks test retrieval efficiency, S tasks capability/availability, B tasks fallback and uncertainty. No combined score is a headline retrieval result.

All 26 are specifications for a future trial, not claims of completed model evaluations. Evidence IDs below are fixture-design labels. The small runnable probe exercises only a few analogous invariants and is not an implementation of the 26-task corpus. Create separate frozen worlds per task; if worlds are reused, retain family clustering in analysis.

Common fixture recipe: use fictional projects North and South, opaque randomized runtime IDs, UTC event times, JSONL sessions and ordinary files. Add balanced distractors with similar names, dates, concepts and repeated text. Vary corpus size and evidence location using precommitted seeds; do not put test answers in filenames, top-level guides or task-specific index fields. Add synthetic sensitivity labels outside the agent mount. The guide documents generic layout and how to select a session/section. Minimal evidence sets listed here are not the only permitted sets: adjudicators may approve equivalent sets, then rescore all arms.

Every task gets answer correctness, evidence adequacy, uncertainty/coverage and identity-integrity scores from 03. M = mechanically verifiable; A = independent annotation; O = owner judgment needed only if replacing the synthetic policy with real user material. Levels indicate a plausible sufficient path, not a required sequence. T01–T12 belong to class E under S0; any required capture here is a pre-existing shared source observation, not state added only to G.

## T01 Exact delivery and content

**Prompt:** Find the retry-policy file delivered for North's timeout request and state the retry count in that delivered version.

**Fixture:** E01 request precedes E02 final reply linking `out/retry.md`; E03 is a contemporaneous frozen capture containing `retries: 3`. A same-named South file says 7; North's later live file says 5.

**Gold:** North delivery D1, captured version V1, count 3. Required set {E01,E02,E03}; allow an independently proven exact copy of E03. A live path alone or a catalog title cannot establish delivered content. False project or latest-version substitution fails. **Labels:** E; object/version selection; L0→L2→L3; M+A.

## T02 Older matching request

**Prompt:** Retrieve the version that answered the original accessibility request, and identify its recommendation.

**Fixture:** Same logical path has D1 for accessibility and D2 for a later board-summary request. E04/E05 bind request/reply for D1; C1 says `increase contrast`. E06/E07 bind D2; C2 says `shorten summary`.

**Gold:** D1/C1 and `increase contrast`, with {E04,E05,C1}. Report D2 only as later context. A grouped result must preserve the matching occurrence; mixing D1 query terms with D2 content fails. **Labels:** E; occurrence-local matching; L1→L2→L3; M+A.

## T03 One handover, multiple files

**Prompt:** Which files were handed over in the reply to the latency review request?

**Fixture:** E08 request and E09 reply name `review.md`, `latency.svg` and `fix.patch`. Adjacent reply E10 names `budget.csv`; a tool observation in the same session names an internal scratch file.

**Gold:** Exactly the three E09 members, attributed to that request/reply, without claiming bundle completeness or authorship. {E08,E09} is sufficient; source files are not necessary for this membership question. Adding neighboring or tool-only files fails. **Labels:** E; handover grouping; L0→L2; M+A.

## T04 No cross-session conjunction

**Prompt:** Find the delivery whose request mentions both retry policy and board presentation; if none is evidenced in the supplied scope, explain.

**Fixture:** Same path appears in session A with `retry policy` and B with `board presentation`; no single request contains both. Manifest M04 certifies the finite fixture sessions and turns.

**Gold:** No request in M04's complete scope satisfies both terms; explain the split between A and B. {A request,B request,M04 plus full enumerated search coverage} supports the bounded negative. Do not declare the file nonexistent. **Labels:** E; scoped negative and false join; L2 plus scope; M+A.

## T05 Rename with explicit continuity

**Prompt:** Where is the artifact formerly called `draft.md`, and what establishes continuity?

**Fixture:** E11 is a recorded successful move from `draft.md` to `report.md` for object O5; two source observations have the same digest and the scoped project ID. E12 is an unrelated `draft.md` in another project.

**Gold:** `report.md` in the specified snapshot, supported by the observed move and byte comparison, scoped to O5. {E11,old/new observations} suffices. Names or digest alone do not establish this logical continuity. **Labels:** E; rename provenance; L1→L3; M+A.

## T06 Transcode is a derivative

**Prompt:** Is `diagram.png` the same byte version as `diagram.svg`, and what relation can be established?

**Fixture:** E13 records a completed transformation with input/output digests and retained files. Similar unlinked image E14 is a distractor. The fixture uses a known deterministic transform, with environment/version recorded.

**Gold:** Different byte versions; the PNG is a recorded derivative of the specified SVG. {E13,input/output hashes or payloads} supports that relationship, not universal semantic equivalence or identical project approval. No transformation is inferred from visual similarity. **Labels:** E; transformation and identity; L1→L3; M+A.

## T07 Same hash across projects

**Prompt:** Do North and South share one approved work item because their templates have the same hash?

**Fixture:** Two explicitly distinct object IDs and project roots contain identical template bytes. Shared source facts include a scoped North-only approval record; no South approval record or identity link exists. This existing record is accessible to both arms.

**Gold:** Byte equality only; preserve two objects and North approval scope. South approval is not established. {both object/project observations,byte digests,scoped approval} required. Merging items or inheriting approval fails. **Labels:** E; identity and scope; L1→L2/3; M+A, O for real authority only.

## T08 Independently referenced member

**Prompt:** Which chart was separately cited after being included in the review bundle?

**Fixture:** Bundle manifest E15 lists `summary.md` and member `chart.svg`; E16 later cites the chart directly. Another chart has the same basename in a second bundle.

**Gold:** The member's own ID/version, its parent-bundle membership and the separate reference. {E15,E16} plus target resolution if ambiguous. Do not collapse the independent reference into the bundle or assume all bundle bytes remain available. **Labels:** E; membership versus reference; L1→L2; M+A.

## T09 Rollback versus latest delivery

**Prompt:** Does the current file match the most recent delivery, and which known version does it match?

**Fixture:** D1 hash H1, D2 hash H2, frozen current bytes hash H1. Both shared captures exist; ordering is explicit.

**Gold:** Current equals D1 and differs from later D2. State byte match, with rollback interpretation qualified unless an actual rollback event exists. {D1,D2,current observation} required; newest timestamp is not proof of current content. **Labels:** E; version comparison; L1→L3; M+A.

## T10 Late first observation

**Prompt:** Can the saved file establish the exact bytes delivered at 10:00?

**Fixture:** Reply at 10:00, first capture at 14:00; no earlier snapshot, trusted write result or byte observation. The file's mtime suggests 09:55 but may have been restored. Capture contains text different from a speculative write input.

**Gold:** Exact delivery-time bytes are not established; describe what was observed at 14:00 and the missing historical evidence. {reply,first-observation record,scope manifest} required. Inferring certainty from mtime or logged intent fails. **Labels:** E; epistemic limit; L1→L2/3; M+A.

## T11 Claimed tests versus observed result

**Prompt:** What test result is actually evidenced for this delivery?

**Fixture:** Final reply claims all tests passed. A linked tool-result record shows `test_timeout` failed; a later command invocation has no result. No final test report exists in the supplied complete session.

**Gold:** Quote/paraphrase the claim as a claim, identify the observed failure and later unknown outcome. {reply,failed result,pending invocation,session scope} required. Neither a request to rerun nor an agent's success phrase establishes a later pass. **Labels:** E; assertion/action/result; L2→L3 log unit; M+A.

## T12 Record shape and reply boundaries

**Prompt:** Which artifact did the user-facing final reply deliver for the Unicode heading request?

**Fixture:** Provider A uses split final-message parts; provider B uses a different JSONL nesting. A subagent mentions a decoy. The selected user-facing reply links `out/说明.md#用法`; a code line anchor elsewhere references `src/main.swift:42`. All raw records and decoding instructions are available.

**Gold:** The document bound to the requested final reply; preserve its heading anchor as a locator, not a new object. {request,all relevant final-message parts,source path observation}. Under the frozen experimental admission rule, neither the subagent decoy nor line-reference example is a delivery. **Labels:** E; adapter/normalization; L0→L2; M+A. Unicode byte spelling remains distinguishable from display normalization.
