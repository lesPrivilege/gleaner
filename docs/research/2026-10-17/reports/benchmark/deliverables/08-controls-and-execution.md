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
