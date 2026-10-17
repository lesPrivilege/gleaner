# Gleaner pointer governance benchmark

Research protocol v0.1 · 17 October 2026 · local proposal registration `GL-RD-PTR-001`

The falsifiable question is whether a pointer/catalog layer helps an equally capable agent reach warranted answers with less work, after charging for preparation and keeping the available information equal. A separate experiment asks what becomes answerable when someone actually records approvals or preserves historical bytes. The catalog cannot create those facts.

This is future R&D, separate from release work. Nothing here commits Gleaner to a schema, CLI, MCP interface, retention policy, or product feature. Future adoption belongs to Opus. Public delivery approval remains pending; these files are a local research registration, not an external preregistration.

Read [01](01-claims-and-design.md) for hypotheses and experiment arms, [02](02-evidence-and-lifecycle.md) for evidence semantics, and [03](03-scoring-and-statistics.md) for measurement. [04](04-tasks-shared-information.md), [05](05-tasks-recorded-state.md), and [06](06-tasks-fallback.md) specify 26 tasks. [07](07-primary-research-and-dataset-atlas.md) links the primary research and dataset sources. [08](08-controls-and-execution.md) covers future execution and controls; [09](09-synthetic-results.md) reports the limited executed probe. Process notes and source-discovery records are outside the protocol in `../evidence/`.

The most consequential design choices are:

- Compare raw retrieval with the same tools plus catalog access. Preserve strong targeted-session and targeted-section baselines.
- Separate shared-information efficiency, captured-state availability, and catalog-blind-spot recovery. Never pool these into one claimed retrieval improvement.
- Use independent evidence judgments. A useful elimination step can matter without appearing in the final answer; unjudged evidence is not automatically irrelevant.
- Freeze source snapshots, adapters, configuration and normalization. A stable live path is not a stable input.
- Treat 26 scenarios as a diagnostic pilot. Repeated model runs measure within-task variability; they do not add independent scenarios.

Public repository context is pinned to [main at 22dd07d926a764f0a2efcdeb093b78f0b9eab41b](https://github.com/lesPrivilege/gleaner/tree/22dd07d926a764f0a2efcdeb093b78f0b9eab41b). [PR #4](https://github.com/lesPrivilege/gleaner/pull/4) was observed open and unmerged, with head `72a42993512281a8bcc36fd9c6f22566132258d9`. PR prose is not executed test evidence for this study.

The repository already distinguishes saved bytes, delivery references and late observations. Its [README](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/README.md) describes a provisional admission rule and missing-file states. The [lifecycle design](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/design/evidence-and-lifecycle.md) discusses derived data, authored corrections and capture preservation. These are useful premises for experiments, not evidence of their effectiveness.

Delivered evidence has three distinct statuses: the written protocol and task specifications are complete; the small local probe checks only synthetic information and lifecycle invariants; real-log trials and repeated-model comparisons are proposed and have not run. No private logs, credentials, paid model API, deployment, push, publication or product edit is part of this work. The saved Praxis checkout is not the research directory and was not modified.

---

# Claims and experiment design

## Estimands and falsifiers

The experimental unit is an independently authored scenario with a frozen source state and a question. An agent episode is one task, condition and repetition. Estimate task-weighted effects for this specified corpus; synthetic results do not estimate everyday user benefit without a separately justified sampling frame.

| Registered claim | Comparison and outcome | What would undermine it |
|---|---|---|
| H1 Retrieval efficiency | On T01–T12, progressive catalog plus raw tools versus the strongest preselected raw baseline, with equal information | Little saving against section search, worse warranted-answer accuracy, or savings erased by preparation |
| H2 Recorded-state availability | On T13–T18, capture absent versus present at fixed retrieval method; also compare retrieval methods within each capture condition | Catalog supplies an approval or historical payload absent from inputs; or the raw arm with the same record performs equally, undermining a retrieval-specific claim |
| H3 Bounded fallback | On T19–T26, catalog plus raw tools versus raw tools, assessing supported answers, warranted uncertainty and declared coverage | Confident global absence after a catalog miss, wrong relinking, or fallback with no advantage over targeted raw search |
| H4 Lifecycle and rebuild | Fixed-source reproducibility and controlled mutation suite | Rebuild loses authored annotations/captures, promotes candidates, merges identities on hash alone, or changes output without an accounted input/config change |

H2 can succeed as a preservation finding while H1 fails. A successfully retrieved approval document establishes the recorded approval within its scope, not an independently verified historical act outside the source contract. Reject any benchmark oracle that turns tool intent into execution or a delivery label into owner approval.

For a later confirmatory study, proposed materiality thresholds are: at least 20% less total model input tokens for H1, a one-sided 95% lower confidence bound on the warranted-answer accuracy difference above −5 percentage points, and no increase in false approvals or identity conflations. Cost success requires the upper one-sided 95% bound on the task-level token ratio below 0.80. These are negotiable utility choices, not literature constants; freeze them before evaluation. The 26-task pilot is generally too small to certify these bounds. Wrong-sided intervals can contradict a claim; intervals crossing a threshold mean inconclusive. Do not reinterpret failure to reject as equivalence. Report token savings even when the accuracy gate fails, labeled as a tradeoff.

For H3, propose a future target of at least 90% valid resolution or warranted uncertainty on eligible cases and at most 5% false global absence, with confidence bounds. Report raw rates and intervals in the pilot; zero observed failures does not establish safety. H4 is a fixture contract: an observed counterexample falsifies that invariant, while passing a small suite establishes only those cases.

## Information sets and causal separation

Let S0 contain frozen source files, observable logs, the same source/format guide and coverage manifest. Let S1 add an independently generated state ledger, owner annotations and pre-overwrite snapshots. Withhold those additions from both S0 arms. Any equivalent facts already present in S0 are not new state: relabel that case as retrieval. Construct the catalog solely from the selected input set, before task prompts or gold labels are revealed. No task-specific headings, summaries, approval labels or gold evidence links may be injected.

| Arm | Information | Access | Purpose |
|---|---|---|---|
| R0 | S0 | Raw toolkit and guide | Raw baseline without newly recorded state |
| G0 | S0 | Exact R0 tools plus catalog | Equal-information retrieval comparison |
| R1 | S1 | Raw toolkit; state ledger and capture files documented in guide | Raw baseline with recorded state |
| G1 | S1 | Exact R1 tools plus catalog | Retrieval effect after state exists |

Estimate G0−R0 and G1−R1 as retrieval effects. R1−R0 and G1−G0 estimate the effect of this capture package, including access overhead. The difference of those differences tests interaction. G1−R0 is an end-to-end bundle effect and must never be called schema retrieval gain. State-dependent payload accuracy and warranted-answer accuracy have different denominators: an honest unknown can be correct in S0 without recovering a missing payload.

S1 is an information-availability manipulation. Capture engineering, annotation time and storage are measured separately; this manipulation alone cannot show that Gleaner would reliably collect the records in practice. Use approval-only and snapshot-only S1 variants on applicable tasks to isolate which component creates availability. Equal raw access to serialized authored state is mandatory even if a future product stores it inside a database.

## Strong baselines and ablations

All arms receive the same pinned model, system policy, query, source permissions, token/time/tool limits, raw tools and non-answer-bearing location guide. Pin `rg`, `jq`, `fd`, shell and decoding utilities. The guide describes layout, record schemas, session identifiers, event versus observation time, encodings, hidden files and safe commands. It must not name the correct session or section for a test question.

R-search permits `fd`/`rg --files` path discovery, `rg` lexical search, `jq` record filtering and range/section reads. R-session first discovers a likely session and then reads it. R-section discovers the session and reads matching turns or sections with adjacent context. Count discovery in both; an oracle-supplied session is only a labeled diagnostic upper bound. Allow simple reusable baseline scripts, scratch lists and generic indexes; charge preparation and maintenance. A baseline can reconstruct a catalog during its budget, making that cost explicit. Do not cripple it by requiring a full-corpus dump.

Use disjoint development fixtures to select and lock the strongest raw recipe. Report all three raw variants so a weak selection cannot hide the section baseline. Select on accuracy first, then total cost. Test results cannot choose the comparator retrospectively. Exhaustive reading is a stress/cost reference, not the principal comparator.

| Ablation | Controlled change | Interpretation |
|---|---|---|
| G-flat | Same fields and facts, flat export with raw search | Organization versus information |
| G-progressive | L0–L3, raw tools always available | Progressive disclosure and navigation combined |
| G-no-summary | Remove only generated descriptive summaries, if later added | Summary benefit and maintenance cost; summaries are excluded in core v0.1 |
| G-catalog-only | Disable raw fallback on blind-spot tasks | Deliberate failure diagnostic; not the proposed system |
| G-stale / G-partial | Freeze an older index or omit known adapter coverage | Robustness to disclosed coverage deficits |
| Oracle evidence | Give independently judged adequate evidence directly | Reader ceiling; not a practical retrieval baseline |

Core v0.1 uses deterministic extraction and no generated summaries. On T01–T12 run R-search, R-session, R-section, G-flat and G-progressive. On T13–T18 run the 2×2 matrix using the locked raw recipe. On T19–T26 run locked raw, G-progressive, G-catalog-only and the applicable partial/stale diagnostic. Keep other ablations exploratory and separate from the primary comparison. This reduced design avoids a needlessly expensive full factorial.

## Progressive interface proposal

L0 is a compact catalog containing discovery descriptors, object IDs, availability qualifiers and coverage status. L1 gives object/version/pointer relations and provenance of each relation. L2 gives exact request/message evidence with stable record IDs and context. L3 resolves the actual source or capture and the relevant original log unit. Levels describe evidence granularity, not trust ranks; a compact authenticated approval record may be sufficient without opening unrelated logs.

Possible commands are `find`, `show`, `evidence`, `resolve` and `scope`. They are an experimental interface proposal, not implementation instructions; an ordinary CLI is sufficient. Raw search can be used at any point and levels can be skipped. Report the actual sequence, deepest level and corresponding source granularity in raw arms. A successful answer must satisfy the rubric, not a prescribed navigation path.

A negative result returns searched collection, input snapshot, adapter/extraction version, covered source kinds/time bounds, unreadable or excluded areas, truncation and next fallback scope. It does not assert absence outside those bounds. Provide source-level candidates without upgrading them to admitted deliveries or confirmed lineage.

---

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

---

# Scoring and statistical analysis

## Answer and evidence rubric

Require a structured answer containing the requested result or uncertainty, object/version identifiers where warranted, evidence references, the scope of any negative claim and unresolved conditions. The visible prompt asks for these fields without revealing the labels. All proposed tasks use the same scoring contract:

1. **Answer correctness:** all required facts correct, including the target version, time and identity; no material unsupported extra claim.
2. **Evidence adequacy:** a valid allowed evidence set supports each material claim at the demanded strength. Merely locating a plausible file is insufficient for a historical-byte or approval claim.
3. **Uncertainty/coverage:** missing or partial evidence is reported accurately, with bounded searched scope and a justified fallback or stop.
4. **Identity/state integrity:** no false merge, invented execution, wrong version approval or promoted recovery candidate.

Primary warranted success is 1 only when all applicable components pass. Also report each component separately and an optional 0–2 diagnostic rating (wrong/partial/complete) for answer and evidence. Do not hide critical failures inside a composite average. A semantically correct answer with invented citations fails evidence adequacy. An accurate qualified unknown on an unanswerable condition can pass primary success, but counts as zero payload/state recovery.

Freeze gold in a separate evaluator-only location. For each task store observable facts, information condition, requested fact, acceptable answer variants, minimal sufficient evidence sets (possibly several), useful elimination evidence, disallowed conclusions and uncertainty requirements. Use stable evidence IDs tied to actual source spans. Mechanically generated fixture truth is not automatically observable truth: mark each gold fact available, unavailable or contradicted in each arm.

Error classes can co-occur: wrong object/project; wrong version/time; false same-hash merge; unsupported lineage; request mistaken for execution; false approval; capture provenance error; false global absence; failed fallback; stale pointer; ungrounded citation; evidence inaccessible; sensitive output; budget exhaustion. Report which class first prevented warranted success, plus all observed classes. Classify missing-information cases separately from retrieval failures.

## Who labels what

Mechanically verify synthetic file hashes, byte equality, manifest completeness, record ordering, explicit event fields, deterministic authority policies, reference existence, task-specific exact values, retention and source/capture availability. Verify tool execution outcomes only from supplied observations or controlled replay. These checks need no owner labeling.

Two independent annotators, blinded to arm/model identity and hypothesis direction, label evidence entailment, useful exploration, semantic answer variants and ambiguous relations. Provide source material and an uncertainty option. Pool candidate evidence from all arms plus a corpus audit, shuffle it, and double-label all 26 pilot tasks and all severe failures. Report raw agreement and a chance-adjusted agreement measure with its prevalence caveat, disagreement counts and adjudication decisions. Labels are frozen before scoring; a newly discovered valid evidence set is versioned and every arm is rescored symmetrically. Annotators cannot use one arm's final answer as the relevance definition.

Owner judgment is limited to facts that are actually personal or normative: who had approval authority, intended logical identity, chosen alias/grouping, whether a specific record counts as consent, and acceptable retention/privacy policy. Record owner rationale and uncertainty. If unavailable, mark these tasks unresolved or substitute a declared synthetic policy; do not invent owner intent. A researcher or independent adjudicator can do the remaining work. The user need not be the sole labeler.

## Metric definitions

| Metric | Definition and reporting |
|---|---|
| Warranted success | Mean task success after averaging repetitions per task; report separately for E, S0, S1 and B, and per task |
| Availability ceiling | Fraction with a sufficient observable evidence set in each information condition; separate from whether the agent found it |
| State/payload recovery | Exact requested state or historical bytes recovered on answerable S tasks; unavailable cases reported separately |
| Evidence recall | Fraction of required evidence facts retrieved, allowing any preregistered sufficient set; report fact coverage and complete-set retrieval |
| Citation precision/coverage | Supported cited claims divided by cited claims; material claims with adequate citation divided by material claims. No citations gives undefined precision, not perfect precision |
| Retrieval rank measures | Optional recall@k/nDCG for fixed ranked candidate lists only, at a specified unit (object, message or span); not interchangeable across units or with agent success |
| Input/output tokens | Actual model usage per episode including guide, tool definitions, catalog, repeated context and failed calls; output and reported reasoning tokens separately. Unknown tokenizer/usage fields remain missing |
| Tool work | Top-level calls, internal suboperations, retries/errors, output bytes and truncated bytes; batched calls do not make backend work free |
| Time | End-to-end wall time, model/tool time, build/refresh time and queue delays; cold and warm-cache results separated on controlled hardware |
| Depth | Counts at L0–L3, transitions and maximum level; raw arm records equivalent source granularity and raw fallback use |
| Raw scope | Unique files, sessions, records and source bytes examined versus eligible corpus; also cumulative scan bytes including repeat scans. Record known instrumentation limits |
| Preparation | CPU time, wall time, peak memory, bytes read/written, index/capture storage, human effort and any model usage; baseline scripts/indexes included |
| Maintenance | Per frozen update epoch: refresh cost, changed/revalidated records, stale pointers, lost reachable evidence, failed repairs and annotation migration effort |
| False absence | Unsupported global-absence answers divided by episodes presenting an absent/partial/omitted target; also report count over all episodes |
| Sensitive exposure | Unique labeled sensitive spans/tokens seen by the model, cumulative presentations and final-answer disclosure; break down task-necessary versus unnecessary exposure |

Instrumentation distinguishes content scanned by a local search engine from content returned to the model. If `rg` cannot expose precise backend bytes, record the query scope and matched/output bytes, label scan bytes an upper bound or unknown, and do not invent precise savings. A wrapper may audit opened files using synthetic inputs only; identical instrumentation applies to all arms.

Evidence relevance has four labels: required support, justified exploration/elimination, irrelevant, and unjudged. Annotators judge exploration in light of the information available before that read, not just the final answer. Report token mass for each category, unique and cumulative. Irrelevant-context fraction is irrelevant tokens divided by all retrieved context tokens; separately report the unjudged fraction and a lower/upper bound treating unjudged tokens as relevant/irrelevant. Path and metadata tokens can be useful evidence. Do not score every uncited passage as waste.

Use synthetic sensitive markers and semantic labels (e.g. a fictional confidential account name), not real secrets. Same authorization and redaction configuration in both arms; give both the same sanitized source view. A separate raw-visibility condition may examine exposure tradeoffs, but cannot masquerade as equal-information retrieval. Missing evidence after redaction is an availability limit. Redaction of snippets does not sanitize underlying saved files.

## Amortization

For method a, report `C_a(Q,U) = P_a + sum(update_cost_a[1:U]) + sum(query_cost_a[1:Q])`. Separate dollars, compute time, human minutes and storage; do not add incompatible units. Include shared capture costs in bundle comparisons and show them cancelling, where appropriate, in equal-information comparisons. Q is queries per corpus lifetime or refresh interval, never repetitions counted as production demand.

If per-query savings d are positive and maintenance difference is fixed, break-even query count is `ceil((P_G-P_R + M_G-M_R)/d)` with a floor of zero. If d≤0 there is no positive finite break-even under those assumptions. Report sensitivity at Q=1, 10, 100 and 1000 and multiple update rates, without pretending these are observed user workloads. The operational claim can fail even when online lookup is cheaper.

## Repetitions and uncertainty

Start with five independent fresh episodes per task/arm as a practical pilot allocation, using one pinned capable model and fixed decoding settings. Randomize arm order in blocks by task/repetition, separate sessions and caches, and balance cold/warm conditions. Pin model build/date and seed when supported; a shared seed does not guarantee paired stochastic trajectories. Never use best-of-five as the main result. Report mean success, all-five success and run-level variation. The all-k success concept follows [τ-bench](https://arxiv.org/html/2406.12045v1); it differs from pass@k, which rewards any successful attempt.

Average within each task before comparing arms. Use paired task-level differences and ratios, with a task-cluster bootstrap (e.g. 10,000 resamples) for intervals and a paired permutation test for a preselected difference statistic when exchangeability is defensible. Related scenarios derived from one base world must be clustered together; also show family-level sensitivity. Twenty-six tasks times five repetitions is not 130 independent tasks. Subgroup intervals from 6–12 tasks are especially unstable. These techniques follow the task-pairing principle, not a universal statistical guarantee; [Smucker, Allan and Carterette](https://doi.org/10.1145/1321440.1321528) study IR significance tests and the choice of statistic.

For illustration, zero failures in 26 independent Bernoulli cases gives a one-sided exact 95% upper failure bound of `1-0.05^(1/26)`, about 10.9%; with 12 cases it is about 22.1%. The actual purposive scenarios are not a random user sample, so even these bounds do not certify production rates. Estimating rare harm needs many more independent opportunities.

Use a disjoint pilot to estimate variance and task-family correlation, then simulate power for a predeclared minimally useful paired effect. Expand independent scenarios before adding many repetitions once within-task variation is understood. Reserve holdout task families, paraphrases and corpus sizes for later validation. Limit confirmatory claims to the primary comparator/metrics, adjust explicitly for multiple formal tests, and label remaining analyses exploratory. Timeouts and budget failures remain failures with censored cost/time; report them rather than dropping expensive runs. Conditional cost among successes is supplementary because selection can bias it.

---

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

---

# Task specifications T13–T18

Class S tasks use the 2×2 information matrix. Every added record and snapshot is independently created before extraction and supplied verbatim to R1 as well as G1. Both S0 arms lack it. State recovery is scored separately from a warranted unknown. These tasks do not demonstrate that a schema creates approval, authorship or missing historical content.

## T13 Version-scoped approval

**Prompt:** Is version V1 approved by the designated owner for the internal review, as of 12:00?

**Fixture:** S0 contains the delivery and an approval request, without a recorded decision. S1 additionally contains A13: owner Mira, authority policy P13, target O13/V1, purpose internal review, approval at 11:00. No publication authorization is implied. Synthetic ledger scope and completeness through 12:00 are supplied.

**Gold:** In S0, unknown/not evidenced; do not say approved or affirm a historical rejection. In S1, the recorded owner approval covers V1 for internal review at that time. Required S1 evidence {P13,A13,target binding}; S0 needs the request and coverage/gap explanation. Wrong version, purpose or authority fails. **Labels:** S; approval availability; L1→L2/source ledger; M+A, O only for real authority/intent.

**Mechanical contrast:** Put A13 in a plain JSONL ledger in R1. Any G1–R0 gain combines capture and retrieval. G1–R1 is the retrieval test.

## T14 Revocation and scope

**Prompt:** Is V2 approved for external publication at 13:00?

**Fixture:** S0 has an agent claim `approved` without owner evidence. S1 includes owner approval for V1/internal review at 11:00, explicit revocation at 12:00 and a request to publish V2 without a decision. Policy P14 says only the owner ledger grants authorization and is complete through 13:00.

**Gold:** S0: authorization unestablished. S1: no valid recorded authorization for V2/publication under P14; distinguish wrong version/purpose and revoked V1 approval. {P14,approval,revocation,V2 request,ledger scope} required. Do not turn an agent claim or absence in a partial ledger into approval or rejection. **Labels:** S; temporal authority; L1→L2; M+A/O.

**Control:** A separately generated variant changes only purpose or version; freeze before evaluation to detect a shortcut that blindly answers no.

## T15 Pre-overwrite payload

**Prompt:** What exact budget value was in the file immediately before the overwrite at 10:05?

**Fixture:** S0 contains a 10:05 overwrite result and current file value 900; an earlier write request contains 600 but has no execution result. S1 adds a captured pre-overwrite payload C15 showing 700, with observation at 10:04:59, digest and a controlled operation sequence proving it is the last version before overwrite.

**Gold:** S0: exact prior value unavailable, even though 600 is a plausible intent. S1: 700 with {C15,capture provenance,ordered overwrite observation}. A hash without payload cannot answer the value. A late capture of 900 fails. **Labels:** S; irreplaceable snapshot; L1→L3; M+A.

**Control:** The capture package must include actual bytes and sequence evidence. Merely calling a record `pre-overwrite` is insufficient unless the fixture contract establishes timing.

## T16 Deleted worktree

**Prompt:** Recover the delivered artifact from a now-deleted worktree, or state exactly what survives.

**Fixture:** S0 has a delivery reference into a worktree, recorded disappearance and a complete fixture inventory showing no retained payload or matching Git object. A similarly named artifact in the main worktree differs. S1 adds a verified historical capture C16 and its original project/worktree identity.

**Gold:** S0: retain the lost-item reference and report payload unavailable within the supplied scope; no claimed recovery. S1: resolve C16 and verify its digest, while identifying the original path as gone. {delivery,disappearance,inventory,C16 and observation when available}. Copying the main-worktree candidate without evidence fails. **Labels:** S; recovery and source ownership; L1→L3; M+A.

**Lifecycle check:** Rebuild must retain the reference and C16 linkage even when the original path cannot be resolved. This is a synthetic invariant, not a command to inspect real worktrees.

## T17 Authored arrangement survives rebuild

**Prompt:** After rebuilding the derived catalog, which object did the owner call `Board packet`, and in which two collections did they place it?

**Fixture:** S0 has two similarly titled objects and no authored arrangement. S1 adds annotation U17 targeting O17/V1 with alias `Board packet`, memberships Review and Archive, explicit scope and an owner event ID. Rebuild from the same raw files; optionally rename a log so the derived occurrence key changes.

**Gold:** S0: arrangement not recoverable. S1: O17/V1, both memberships, with {U17,target-binding/reconciliation evidence}. If the target cannot be reconciled, preserve U17 as unresolved rather than moving it to the similar item. Snapshot/annotation files survive derived-index deletion. **Labels:** S; authored state; L1→L2; M+A/O.

**Control:** An alias is not a filesystem rename, collection membership is not ownership, and this annotation does not approve later versions. Measure migration failures and recovery effort, not just whether an annotation file remains on disk.

## T18 Missing-state negative control

**Prompt:** Did the owner approve the overwrite, and did the requested write actually execute?

**Fixture:** Both S0 and S1 contain an approval request and a write tool invocation with no result. S1 adds unrelated well-formed state records, but no decision or execution observation for this operation. The fixture explicitly allows an unobserved outcome; the hidden world may vary while visible evidence is identical.

**Gold:** Neither approval nor execution is established in either condition. Cite the two attempts and incomplete observation boundary; identify the precise missing decision/result evidence. Do not say the action failed or was rejected. No amount of catalog structure changes this answer. **Labels:** S; information-theoretic limit; L2→L3 log unit plus scope; M+A.

**Control:** Construct two hidden worlds with identical visible inputs and different actual outcomes. The agent is graded on warranted uncertainty, not omniscience. Annotators must not leak the hidden bit into labels, index descriptors or the question. This is the most direct falsifier of unsupported catalog authority.

---

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

---

# Primary research and dataset atlas

These sources inform design choices; none establishes that Gleaner's pointer layer will help. Titles are retained in their primary English wording and links point to original papers, official specifications or author-maintained repositories/cards. No historical bibliographic claim or new-paper novelty claim is asserted here. Read 01–03 for the actual proposed protocol.

## Evaluation practice worth transferring

| Primary source | What it supports | Limit for this experiment |
|---|---|---|
| [Text REtrieval Conference overview, NIST](https://trec.nist.gov/overview.html); Buckley and Voorhees, [Retrieval Evaluation with Incomplete Information](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=150469) (2004) | Separate documents, topics and relevance judgments; incomplete judgments can distort evaluation | A catalog miss is not a corpus absence; do not classify unjudged spans as irrelevant or assume a pooled set is exhaustive |
| Thakur et al., [BEIR: A Heterogeneous Benchmark for Zero-shot Evaluation of Information Retrieval Models](https://arxiv.org/html/2104.08663v4) (2021) | Heterogeneous tasks, strong lexical baselines, retrieval cost tradeoffs and judging-pool bias | Passage ranking results do not measure historical-byte recovery or approval authority; retain targeted command-line baselines |
| Gao et al., [Enabling Large Language Models to Generate Text with Citations](https://aclanthology.org/2023.emnlp-main.398/) (ALCE, 2023) | Separate answer correctness and citation quality | Citation entailment does not measure necessary exploratory reads or verify execution; automatic judges need calibration |
| Wu et al., [LongMemEval: Benchmarking Chat Assistants on Long-Term Interactive Memory](https://arxiv.org/html/2410.10813v2) (ICLR 2025) | Extraction, multi-session reasoning, temporal reasoning, updates and abstention; evidence-location labels and indexing/retrieval/reading separation | Constructed histories and model-assisted evaluation are not owner-authorized workflow ground truth |
| Maharana et al., [Evaluating Very Long-Term Conversational Memory of LLM Agents](https://aclanthology.org/2024.acl-long.747/) (LoCoMo, 2024) | Human-checked generated long conversations and temporal/event structure | Human editing of dialogue does not turn a fictional event into an observed file operation |
| Yao et al., [τ-bench: A Benchmark for Tool-Agent-User Interaction in Real-World Domains](https://arxiv.org/html/2406.12045v1) (2024) | End-state comparison and repeated all-k success rather than any-of-k success | The paper notes end-state reward can miss policy violations such as missing confirmation; add trajectory/evidence checks. The legacy repository now warns its tasks are outdated |
| Smucker, Allan and Carterette, [A Comparison of Statistical Significance Tests for Information Retrieval Evaluation](https://doi.org/10.1145/1321440.1321528) (2007) | Match a paired significance test to the reported statistic and experimental assumptions | Does not justify population claims from 26 purposive scenarios or treat repeated episodes as independent queries |
| Kapoor et al., [Holistic Agent Leaderboard: The Missing Infrastructure for AI Agent Evaluation](https://arxiv.org/html/2510.11977) and [official HAL site](https://hal.cs.princeton.edu/) | Cost-aware evaluation, scaffold sensitivity, harness controls and trajectory inspection for shortcuts | Standardized harnesses do not remove all benchmark leakage or establish correctness of every logged claim |
| [W3C PROV-DM](https://www.w3.org/TR/2013/REC-prov-dm-20130430/); [ReproZip developer guide](https://docs.reprozip.org/en/stable/developerguide.html) | Provenance distinctions; trace versus post-execution configuration; reproducibility inputs | A provenance vocabulary does not create missing evidence; raw history and environmental observations have different availability |

These are compatible methodological lessons, not a manufactured consensus that catalog governance improves agent work. A positive result must survive strong section retrieval and total-cost accounting. A negative result may show that good raw tooling already captures most benefit, that the task family needs additional preserved state, or that the proposed abstraction hides essential evidence.

## Dataset source, license and access atlas

Status is based on public documentation observed on 17 October 2026. No full dataset, private trajectory or paid-model execution was obtained. Public card access is not the same as verifying every shard, artifact dependency, execution result or reuse right. Before a trial, pin the chosen dataset revision, file hashes, splits, upstream repository commits and applicable notices; do not use moving `main` as the experimental identity.

| Candidate and primary access | Useful content / evidence limit | Observed license and adoption status |
|---|---|---|
| [SWE-bench/SWE-smith-trajectories](https://huggingface.co/datasets/SWE-bench/SWE-smith-trajectories), [raw card](https://huggingface.co/datasets/SWE-bench/SWE-smith-trajectories/raw/main/README.md), [author toolkit](https://github.com/SWE-bench/SWE-smith) | Agent messages, task IDs, patches and resolved labels from generated repair tasks. Useful for paths, tool-result shapes and long traces. A resolved label is not an owner approval or proof of every action | Card declares MIT; preserve upstream repository licenses for embedded code. Public card and split schema verified; shards not fetched. Candidate for a later public-log transfer set |
| [nebius/SWE-agent-trajectories](https://huggingface.co/datasets/nebius/SWE-agent-trajectories) | Trajectories, patches, exit statuses and evaluation logs; useful to distinguish attempted steps and recorded test outcomes. Missing artifacts remain missing | Card states CC BY 4.0, requires respecting each repository's license and flags Llama 3.1 output-license conditions. Public card read; no artifact replay. Candidate with per-source provenance review |
| [SWE-Gym/OpenHands-Sampled-Trajectories](https://huggingface.co/datasets/SWE-Gym/OpenHands-Sampled-Trajectories), [raw card](https://huggingface.co/datasets/SWE-Gym/OpenHands-Sampled-Trajectories/raw/main/README.md) | Messages, tools, run IDs, resolved flags and test-result structures, including null test outputs. Useful schema diversity; flags alone do not prove detailed history | Retrieved card has no explicit dataset license field. Do not infer a data license from OpenHands software. Hold ingestion/redistribution pending a verified applicable notice |
| [LongMemEval cleaned](https://huggingface.co/datasets/xiaowu0162/longmemeval-cleaned), [cleaned card](https://huggingface.co/datasets/xiaowu0162/longmemeval-cleaned/raw/main/README.md), [author repo](https://github.com/xiaowu0162/LongMemEval) | Questions, answers, evidence sessions, dates, updated facts and abstention. Good supplement for temporal retrieval, not executed agent provenance | Card declares MIT. Histories include constructed and upstream dialogue material; record origins/notices. Public card and repository read. Pin cleaned or original explicitly; never mix scores silently |
| [LoCoMo author repo](https://github.com/snap-research/locomo), [LICENSE.txt](https://github.com/snap-research/locomo/blob/main/LICENSE.txt) | Public `data/locomo10.json` offers conversation, QA and event annotations; image references may be external. Generated/human-edited conversations supply no real approval facts | Repository license is CC BY-NC 4.0. Keep out of the default product-related corpus until intended-use compatibility or permission is established; retain as methodological reference |
| [BEIR author repo](https://github.com/UKPLab/beir), [code license](https://github.com/UKPLab/beir/blob/main/LICENSE) | Diverse corpus/query/qrels formats for retrieval controls. Not tool trajectories; selected sets can stress lexical/dense differences | Code Apache 2.0, constituent datasets have their own licenses/access conditions. Select and audit a specific constituent before ingestion; never inherit one blanket data license |
| [ALCE author repo](https://github.com/princeton-nlp/ALCE), [code license](https://github.com/princeton-nlp/ALCE/blob/main/LICENSE) | ASQA, QAMPARI and ELI5-based examples and retrieved passages, citation scoring and human-evaluation material | Repository MIT; upstream question/corpus rights still need separate review. Suitable for scoring-method calibration, not schema/state availability claims |
| [τ-bench author repo](https://github.com/sierra-research/tau-bench), [license](https://github.com/sierra-research/tau-bench/blob/main/LICENSE) | Synthetic policies, tools, task intents and environment states; useful precedent for deterministic oracles | MIT repository. Current README redirects users to later corrected benchmark versions. Use the cited original paper for methodology; any data adoption requires selecting and pinning a specific version. Do not run model-backed simulations here |
| [HAL official site](https://hal.cs.princeton.edu/) and [paper](https://arxiv.org/html/2510.11977) | Public trajectory-analysis precedent and multiple benchmark families | No uniform log-corpus license/access audit completed here. Hold ingestion; individual benchmark/log rights and sensitive content require checks |

Two concrete version traps affect planning. The [original LongMemEval card](https://huggingface.co/datasets/xiaowu0162/longmemeval/raw/main/README.md) directs readers to a cleaned version that removes conflicting/noisy history sessions. The [SWE-smith raw card](https://huggingface.co/datasets/SWE-bench/SWE-smith-trajectories/raw/main/README.md) retains a historical 5,017-trajectory description while current metadata enumerates larger `tool`, `xml` and `ticks` splits. Do not equate those rows with independent tasks: count unique task/trajectory identities after pinning, identify equivalent format variants, and keep them within one split/cluster.

Begin with locally authored fictional fixtures because the necessary approval and snapshot truth can be controlled. Use public trajectories later for format realism and retrieval transfer, with manually audited observable evidence. Neither route substitutes for eventual authorized real-task validation. Do not scrape private logs or reconstruct private identities from public traces.

---

# Controls, execution and proposal registration

## Leakage and fairness checklist

- Freeze task text, gold, input sets, adapters, extraction config, model version, prompts, baseline recipes, budgets and metrics before scored runs. Timestamp and hash the registration locally; external/public preregistration needs separate authorization.
- Keep the corpus builder separate from the question/gold builder where practical. The catalog builder sees source inputs but never task questions, answer rubrics or oracle evidence IDs. Gold and these specification files are outside the agent sandbox.
- Split by base world, project/repository, session, artifact lineage and generator template, not just by question row. Keep alternate trajectory renderings and repeated tasks together. Hold out adversarial families and paraphrases rather than tuning until all visible cases pass.
- Randomize IDs, file order, evidence position and distractor names under frozen seeds. Counterbalance correct alternatives. Questions must not contain object IDs or locators absent from the natural request unless the task specifically tests resolving a supplied pointer.
- Same model, decoding budget, system rules, permissions, tools, redaction and source availability in matched arms. Account for catalog tool descriptions and raw format guides in context tokens. Record prompt lengths and model-visible differences.
- Preserve raw `rg`/`jq`/`fd` competence, section selection, hidden-file handling and structured-record filters. Discover the correct session/section within budget. Use equivalent generic path/format help. No oracle hint in the baseline, catalog or task title.
- Build all indexes before prompts are available. Charge complete-corpus build and update costs, including scans of irrelevant sources. Charge comparable baseline indexes/scripts and manual preparation. Report cache residency, warmup and common shared costs.
- Disable external web/search, dataset lookup, arbitrary network, credential access and access to evaluator files in future model trials. Read source text as evidence, never as new instructions. Synthetic prompt-injection distractors may form a separately registered stress set.
- Reset per episode: filesystem view, index state, model conversation, scratch files, permissions and mutable state. Prevent memory across arms. A rebuild experiment deliberately varies only its declared factor.
- Preserve original bytes and primary-language text; versions of translated prompts are separate conditions. Document Unicode/encoding and line-ending handling. Include multilingual paths without assuming normalized names denote the same file.
- Collect failures, timeouts, truncations and denied reads. No silent retry-until-success, dropped runs, hidden human assistance or best-of-k headline result. Log hardware and queue contention so tool latency is interpretable.
- Blind annotators to method. Pool evidence across methods plus independent corpus review. Record alternative sufficient sets and unresolved labels; apply rubric changes symmetrically. An LLM judge, if later used, is a secondary calibrated measure, not the sole source of truth.
- Separate sensitive-data exposure from answer quality. Use fictional markers, maintain equal access policy and label semantic sensitivity independently. Record both model input exposure and final disclosure. No real credentials or private source material in this stage.

## Practical future execution sequence

1. Implement the full fixture builder in an isolated research harness, never the saved Praxis checkout. Validate source/evidence references and per-arm observability before running models. The delivered small probe is insufficient for this step.
2. Have an independent annotator check scenario ambiguity, authority assumptions, alternative evidence and observable versus hidden truth. Use owner review only for explicitly personal judgments if real tasks are later introduced.
3. Freeze a disjoint development set; tune the raw baseline and catalog interface only there. Verify raw scripts can answer known checks and that both arms can open identical source/capture bytes.
4. Produce a complete manifest and hash the registration. Archive model prompt/tool definitions and deterministic extraction outputs. Check identical-input rebuilds, one-factor mutations and annotation/capture retention.
5. Run the reduced matrix from 01 with five fresh repetitions initially, one model, balanced arm order and the same budgets. No model/API execution is authorized by this research delivery; obtain the separate future trial authorization when an actual runner/model/budget is selected.
6. Score independently, inspect severe errors, report all episodes and every denominator. Publish class-level accuracy, cost, evidence, scope and exposure, then amortization sensitivity. Declare pilot limits; plan independent holdout expansion before a confirmatory claim.
7. Public trajectories can add a separately reported transfer set after dataset pin/license/access checks. Real user tasks require explicit authorization, minimization and an observation-based label plan. Do not retrospectively use unavailable private facts as the answer key.

Recommended result rows are `task_id, family_id, information_condition, arm, repetition, model_revision, corpus_hash, extractor_hash, prompt_hash, answer_status, warranted_success, component_scores, error_classes, evidence_ids, available_gold_facts, deepest_level, tool_calls, backend_ops, source_scope, token_usage, wall_time, exposure, stop_reason`. Keep build/update runs in separate linked rows. Store raw measured values before aggregating. Unit names and missing-value reasons are mandatory.

The report should answer: Which tasks improved? Which facts became available only because of capture? Did section search eliminate the advantage? How much preparation is required before the savings repay it? Which catalog misses needed fallback? Did a layer reduce unnecessary exposure or merely move it into preparation? Which errors are unresolved at the chosen sample size?

## Separately registered future proposals

| Local registration | Scope | Current status / adoption |
|---|---|---|
| GL-RD-PTR-001 | Equal-information catalog retrieval, progressive access and bounded fallback; 26-task pilot protocol | Proposed, no model trials; Opus decides future adoption |
| GL-RD-STATE-002 | Capture/annotation availability, lost-item evidence, version/approval scope and rebuild lifecycle | Proposed, small synthetic contract checks only; no retention or product policy imposed |
| GL-RD-TRANSFER-003 | Audited public-trajectory transfer and eventual authorized real tasks | Proposed, source/license atlas only; no dataset ingestion or private-log access |

These registrations are separate from release work and PR #4. Their implementation, product scope and public delivery are not approved here. No issue, PR, external page, commit, push or deployment has been created. If a later commit is authorized, both author and committer must be `GPT Task <gpt-task@example.invalid>`.

## Evidence already available and remaining work

This delivery supplies the research design, source atlas, 26 specifications and a small safe synthetic probe. The probe establishes only its explicitly logged invariants on its generated fixture. It does not run Gleaner, replicate the earlier ten-task study, benchmark an LLM, certify the 26 tasks, or support any token/latency advantage claim.

The supplied account of an earlier separate scripted probe reports 10/10 across strategies, with bytes: exhaustive 130,205,624; targeted full 394,437; targeted section 5,967; catalog 4,885. Its files and measurement definitions were not supplied here, so those figures are motivation only and excluded from this study's evidence, tables and statistical analysis. In particular, the reported gap between section search and catalog should motivate a strong comparator, not a claimed effect size.

Remaining future work is concrete: author and validate the complete frozen corpus; pin the actual catalog and raw adapters; obtain independent labels; choose and authorize a model/runtime/budget; run repeated episodes; and expand independent holdout scenarios if a confirmatory claim is desired. Public delivery approval remains pending. No private-data or paid-API step is needed to review this proposal.

---

# Executed synthetic probe

The local probe passed 10 of 10 fixture contract checks. This is not a 10-task retrieval result: there were zero model trials and zero compared retrieval strategies. It neither implements nor validates the 26-task benchmark corpus.

Reproduce in the isolated research directory with `python synthetic/probe.py --out run-002` (or another unused simple directory name). The script refuses to overwrite an existing run. It uses Python's standard library, fictional local data and no network or model API. It never runs Gleaner or any repository program. The only deletion is its own newly created derived-output directory during the lifecycle check.

The original execution was `python synthetic/probe.py --out run-001`; evidence is [results.json](../synthetic/run-001/results.json), [input manifests](../synthetic/run-001/fixture-manifests.json) and [configuration](../synthetic/run-001/config.json). The [script](../synthetic/probe.py) SHA-256 at execution was `8c4b6cc1625f62da1d54edf72fc66e8eb70aa608d38acdeea16c74802d5f06f4`. Results record the interpreter, timestamp and exact check outcomes.

| Checked invariant | Observed result | Practical limit |
|---|---|---|
| Equal hash, distinct projects | Two records survive with the same payload hash | Does not test a production identity resolver |
| Equal S1 information | Raw ledger/capture and projection contain the same supplied state | No retrieval-efficiency measurement |
| Missing S0 state | Neither representation supplies a decision or historical snapshot | Missing evidence does not imply a negative real-world event |
| Intent versus fact | V2 approval request remains unsupported; write request has no result; proposed 600 differs from captured 700 | A constructed contrast, not external historical verification |
| Hidden outcomes | Opposite hidden approval outcomes share identical visible input hashes | An agent cannot warrant the hidden distinction from these inputs |
| Partial coverage | Two of three declared source units covered; scope remains open | No agent fallback behavior tested |
| Deterministic rebuild | Canonical output identical after input enumeration reversal | Only this small deterministic projection/configuration |
| Source drift | New input identity and payload mismatch after a controlled path replacement | Drift is distinct from nondeterminism |
| Configuration identity | Extractor-version change alters input identity | Does not prove either extractor is semantically correct |
| Lifecycle separation | Annotation/capture inputs unchanged and reachable after deleting/rebuilding derived output | Does not exercise Gleaner's registry, migrations or admission changes |

The fixture includes a capture value 700, current value 900 and an unexecuted requested value 600 to make unsupported history inference visible. These values are artificial and are not observations about user work. The probe has no token counts, benchmark latency estimates, model accuracy or public/private-log generalization result.

Source inspection, protocol design, synthetic invariant checks and future model trials are separate evidence classes. The first three have artifacts here; the fourth remains proposed. See [controls and execution](08-controls-and-execution.md) for the work required before a scored trial.
