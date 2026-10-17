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
