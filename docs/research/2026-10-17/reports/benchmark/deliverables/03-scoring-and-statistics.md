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
