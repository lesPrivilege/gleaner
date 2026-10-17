# 1. Findings and scope

Research date: 2026-10-17 UTC. This is an independent future research stream. Nothing here changes Gleaner v0.1, adopts a lifecycle contract, or authorizes implementation, deployment, or publication.

## Conclusions

Retrospective reconstruction is established research and implementation practice. The useful opportunity is a careful application to agent-delivered artifacts: preserve declarations, observations, uncertainty, retrieval routes, and human decisions without claiming more history than the evidence supports. There is no basis for claiming invention of retrospective provenance, inferred lineage, source pointers, or provenance graphs.

Three questions must remain independent:

1. **What was declared?** A user-facing reply named an artifact, or asserted that an operation succeeded.
2. **What bytes can be obtained?** From a surviving file, immutable Git object, checkpoint, logged payload, or deterministic reconstruction.
3. **What connects those bytes to that delivery or derivative edge?** A specific observation or execution chain, its coverage, and its assumptions.

The strongest practical invariant is: **never replace a missing observation with a confident narrative**. An unavailable delivery, an uncertain candidate, and a rejected linkage can all remain useful catalog records.

## Terminology that avoids a false novelty claim

| Term | What it means here | What it does not establish |
|---|---|---|
| Prospective provenance | A recipe, planned workflow, declared inputs and outputs | That a particular execution happened |
| Retrospective provenance | Description of a particular execution or history | That its recorder was installed afterward |
| Post-hoc extraction | Convert surviving logs, commits, or other records into provenance | That the original records are complete or trustworthy |
| Inferred / possible provenance | Histories consistent with observations and a stated model | A unique observed causal history |
| Preservation | Keep identified bytes and their evidence available | Their authorship, correctness, or approval |

YesWorkflow demonstrates recorder-free inference with assumptions about script annotations and file organization; Git2PROV converts existing version history; document-similarity research reconstructs plausible legacy-document chains. Blount et al. explicitly distinguish observed and possible provenance. These are direct counterexamples to “all existing systems require prospective instrumentation.” See the exact papers and limits in [Part 2](02-paper-atlas.md).

Conversely, PASS, noWorkflow, and ReproZip show that automatic or non-intrusive collection can still depend on execution-time capture. “No manual code instrumentation” is not equivalent to “recover any past run.”

## Pinned Gleaner context

Public repository: [lesPrivilege/gleaner](https://github.com/lesPrivilege/gleaner).

- Main inspected at **22dd07d926a764f0a2efcdeb093b78f0b9eab41b**; tree **ea7c7e601be4f5a178159964028500d501d590c4**.
- [PR #4](https://github.com/lesPrivilege/gleaner/pull/4) was **open, unmerged** when read. Its base was the main SHA above; head **72a42993512281a8bcc36fd9c6f22566132258d9**. The API's merge-test SHA is not a merged release.
- Inspection was selective, read-only, and through the public repository. No application build, production corpus, or provider account was examined.

The pinned [SPEC](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/SPEC.md) makes final delivery replies the admission evidence, leaves originals in place, uses paths as v0.1 artifact identity, and distinguishes delivery, observation, and capture times. Review/approval and identity relinking are deferred. Its ten-minute/mtime rule is a product classification; this research does not treat it as proof of historical byte identity.

The source inspection establishes these particular research seams:

| Existing implementation evidence | Future research implication |
|---|---|
| [Indexer.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Indexer.swift) derives a delivery ID from log path, first evidence line, and artifact path | Rewritten, relocated, or branched transcripts need identity tests before durable corrections attach to these IDs |
| [Registry.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Registry.swift) refreshes extraction-derived fields; removal of newly inadmissible deliveries deletes their capture rows while stored copies remain | An evidence-retention or correction layer would need its own persistence and explicit supersession rules |
| [ClaudeCodeAdapter.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/ClaudeCodeAdapter.swift) uses tool events to identify final reply text; [CodexAdapter.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/CodexAdapter.swift) admits final-answer messages | A separate corroboration adapter could inspect supporting events without widening the delivery-admission rule |
| [SessionLog.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/SessionLog.swift) preserves per-record line/time/cwd in reply parts | Natural message/tool-call evidence units can build on existing granularity, with source-version validation |

These are scoped observations, not a bug report or requested product edits. PR #4's thread/outline/timeline work is context only; its reported tests were not rerun or independently validated.

## The artifact hypothesis

“Logical artifact = pointers + schema annotations + governance state” is a useful catalog view, but incomplete as an identity rule. Add an identity policy, immutable representation/version references when available, and evidence for each assertion. A pointer is a retrieval route; two pointers can reach one representation, and one path can successively refer to different logical objects. Same bytes can belong to separate independently authored objects.

Source systems may retain originals, but that is a deployment assumption with a measurable retention horizon. Without a surviving immutable source version or authorized snapshot, the catalog cannot guarantee future byte retrieval. A cache becomes the only surviving preservation copy if the original disappears; it then needs a different deletion policy from a disposable search index.

The candidate/cataloged/versioned/reviewed labels remain exploratory. A reviewed item may have unavailable bytes; an unreviewed item may have exact preserved bytes. Separate axes usually express this more honestly than a single maturity ladder.

## Useful now, later, unsupported

**Useful now for research:** evidence taxonomy; natural evidence units; deterministic synthetic probes; source/version manifests; explicit unavailable states; separate authored corrections from extraction; source-specific checkpoint capability notes.

**Later, after evaluation:** bounded reconstruction adapters, identity linking, reviewed derivative edges, permission-aware enterprise disclosure, and a generalized resolver shaped by a real second domain.

**Unsupported:** recovering arbitrary text from edit logs; treating a Write call as success; treating a successful shell exit as complete provenance; treating timestamps, identical bytes, or Git rename similarity as logical identity; assuming checkpoints exist or persist; claiming a generic knowledge graph is required; claiming retrospective provenance itself is novel.

Catalog/card-index metaphors in discussion are analogies only. No historical catalog claim is relied on here. CLI/MCP transport and memory-system nearest-neighbor research are outside this stream.
