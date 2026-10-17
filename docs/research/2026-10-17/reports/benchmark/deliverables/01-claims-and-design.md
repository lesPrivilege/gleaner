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
