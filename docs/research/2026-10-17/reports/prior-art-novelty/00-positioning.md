# Gleaner: independent related-work and novelty review

Research round: 2026-10-17. This is a bounded public-source review, not a publication-novelty guarantee or an implementation audit. No model trial or benchmark was run.

**Assessment:** the broad combination of cross-provider history retrieval, progressive agent consumption, source citations, explicit uncertainty, and handoff is already substantially occupied. The most defensible question concerns **recovering and selecting declared deliverables at the correct artifact version under incomplete retrospective evidence**. A useful systems contribution could establish where that narrower task benefits from declaration-gated indexing, and where the gate loses necessary information.

The proposed direction is treated as a hypothesis: a retrospective, read-only, cross-provider artifact catalog over local agent logs, with “assistant-facing delivery declarations” gating admission and a compact discovery → version/pointers → evidence → original-source path. Here “read-only” means no modification to producer logs or project files; maintaining an index or snapshot store still writes derived or preserved data.

## The comparisons that change the positioning

1. **Cass is a direct retrieval/handoff neighbor.** Its documented robot interface includes bounded search, drill-down, cited extractive packs, freshness and readiness signals. Its source also distinguishes canonical message coordinates from verified physical log spans. Therefore “an agent can search other agents' histories and receive compact evidence” is not a new problem formulation. [Cass documentation][cass]; [citation verification implementation][cass-code].
2. **AgentsView is a direct provenance-aware retrieval neighbor.** Its focused MCP memory surface has coverage states and revision-bound transcript reads. Its public synthetic verification protocol checks fresh-session recall and citations across Claude Code and Codex. These are stronger counterexamples than a human-facing viewer. It also documents immutable exchange of normalized session revisions. These are not versions of produced files. [MCP contract][av]; [verification protocol][av-eval]; [session exchange][av-sync].
3. **Obelisk overlaps the separation of evidence and decisions.** Its retrieval guidance treats approved memory notes as synthesis to check against raw session evidence; it also documents provider-specific limits on superseded history. [Retrieval semantics][obelisk].
4. **Memory research is not uniformly lossy or uncitable.** MemGPT searches stored conversation history; A-Mem includes original interaction content alongside generated metadata; Zep describes raw episodes linked to derived facts, and Graphiti exposes those structures in public code. These do not establish reliable delivered-file identity, but invalidate a summary-only comparison. [MemGPT][memgpt], [A-Mem][amem], [Zep][zep].
5. **The evaluation neighborhood has advanced.** LongMemEval-V2 evaluates evidence gathering from past agent trajectories; FileGram includes file actions and content deltas. Neither reviewed protocol directly scores declaration-gated, exact delivered-file handoff. [LongMemEval-V2][lme2]; [FileGram][filegram].

## Claims to retain, revise, or drop

| Claim from the discussion | Independent assessment |
|---|---|
| Older search is mostly human-oriented | Too broad to support. Name a particular interface and date. Cass, AgentsView, machine-readable protocols, and agentic retrieval research are concrete counterexamples. |
| Agents cannot judge snippets | False as a universal claim. ReadAgent and A-RAG explicitly use compact representations to choose fuller reads. Measure errors and stopping behavior instead. [ReadAgent][readagent]; [A-RAG][arag]. |
| Frontier memory is always opaque, probabilistic, summary-only, uncitable | Conflates model internals, consumer products, APIs, and external stores. Anthropic's memory tool is client-side file access. Proprietary internals remain unknown; public interfaces do not justify claims about them. [Official memory tool][claude-memory]. |
| Providers must expose local logs | An adoption assumption, not a universal obligation. A successful adapter proves access to particular observed versions and settings, not future retention or completeness. |
| The adapter is the only external dependency | Unsupported. Availability, retention, event semantics, path resolution, source revisions, file survival, tool outputs, and optional models all affect the research guarantee. |
| Thin or agent-generated adapters eliminate maintenance bottlenecks | Unproven. Small code can depend on large semantic assumptions. Evidence for LLM-assisted migrations does not establish reliable detection of silent log omissions. [Migration case study][migration]. |
| The whole combination is unexplored | Not established. Several neighbors implement large subsets; no exact match found in this round is a search result, not a uniqueness proof. |
| Small open implementation plus reproducible benchmark is feasible | Plausible. Admission, identity, pointer validity, and coverage behavior can first be measured without paid model calls; agent-benefit claims still require an agent evaluation. |

## A narrower, falsifiable contribution

Candidate positioning: **an empirical study of declaration-gated artifact retrieval and version-correct handoff from heterogeneous, incomplete agent records**. The contribution would be the operational task definition, evidence limitations, and measured tradeoffs against strong existing retrieval systems—not a claim to invent agent memory, progressive disclosure, provenance, or portable context.

Keep four questions separate:

- Was an artifact declared delivered, and to whom?
- Which logical object and version does the declaration refer to?
- Which bytes and source statements can actually be recovered?
- Does a later agent perform better with this catalog at a fixed resource budget?

A declaration establishes a recorded claim of delivery, not acceptance, correctness, successful tool effects, or byte capture. Equal hashes identify equal observed bytes under the chosen hash assumptions; they do not establish logical identity. Identical templates can be different objects, and revisions of one object can differ in hash and path.

Stable query results require a frozen corpus, parser/index versions, filters, ranking configuration, tie-breaking and ordering; stochastic transforms must be pinned or repeated. Stable execution on that snapshot is not universal determinism. Likewise, a schema fingerprint or unchanged parse count does not prove semantic coverage: harmless fields can trigger alarms, while dropped events or changed roles can preserve syntax and counts.

## Grounding and limits

Gleaner was read at **22dd07d926a764f0a2efcdeb093b78f0b9eab41b**. Its README describes a macOS deliverable browser with provisional final-reply admission, saved file copies, and observation-status distinctions; it does not establish the proposed CLI/MCP research claims. [Pinned README][gleaner]. PR #4 was not examined or incorporated.

The atlas distinguishes paper methods, current documentation, code inspected, and unverified implementation claims. No competitor performance was independently reproduced. Absence of a feature in reviewed material is marked unestablished rather than impossible. Public-source search is incomplete, particularly for unpublished systems and changing products.

Read next: [nearest-neighbor matrix](02-comparison-matrix.md), [related-work atlas](01-related-work-atlas.md), [existing evaluations](03-existing-evaluations.md), [experiments and open questions](04-experiments-and-questions.md). The separate [search/access log](90-search-access-log.md) records scope, pins, access failures, and evidence depth.

[cass]: https://github.com/Dicklesworthstone/coding_agent_session_search/blob/6bc477a97dc6b0b55f3019753adf5860a2713b8e/README.md
[cass-code]: https://github.com/Dicklesworthstone/coding_agent_session_search/blob/6bc477a97dc6b0b55f3019753adf5860a2713b8e/src/search/pack_planner.rs#L1200
[av]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/mcp.md
[av-eval]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/internal/agent-memory-verification.md
[obelisk]: https://github.com/tommy0103/obelisk/blob/a4b7329e1fcb8d907ec1f1c9543a26513d87631c/skill-doc/references/retrieval-semantics.md
[memgpt]: https://arxiv.org/html/2310.08560v2
[amem]: https://arxiv.org/html/2502.12110v11
[zep]: https://arxiv.org/html/2501.13956v1
[readagent]: https://arxiv.org/html/2402.09727v3
[arag]: https://arxiv.org/html/2602.03442v1
[lme2]: https://arxiv.org/html/2605.12493v1
[filegram]: https://arxiv.org/html/2604.04901v1
[claude-memory]: https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
[migration]: https://arxiv.org/html/2504.09691v1
[gleaner]: https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/README.md
[av-sync]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/artifact-sync.md
