# Falsifiable experiments and open questions

Research recommendations, 2026-10-17; no experiments were run. See [existing evaluations](03-existing-evaluations.md) for reusable protocols and their limits. This is a discrimination plan, not a product architecture.

## Minimal discriminating experiments

Start with authored public fixtures and openly licensed data, not private user logs. The coordinator reports a companion 26-task pilot with a 2×2 information design separating index benefit from newly captured state; use that design rather than duplicate it here. Seek coverage of two real provider record shapes and a held-out shape. Treat a small pilot as diagnostic, not a powered generalization claim. Keep development and evaluation families separate. Deterministic extraction and pointer tests require no model.

| Hypothesis | Controlled comparison | Measurement and falsifier |
|---|---|---|
| **H1: Declaration admission improves artifact selection** | Declaration gate vs every mentioned path vs tool-edit paths vs a plain file index; use the same corpus, retriever and byte store. Include oracle admission as a separate upper bound | Admission precision/recall and correct selected object/version. Falsified if exclusion losses erase precision gains, or matched-budget raw retrieval performs equally well |
| **H2: Version evidence reduces wrong-file transfer** | Same catalog with/without explicit version evidence. Include overwrite, rollback, rename, equal-content distinct objects, same path reused for a new object, and delayed backfill | Exact-byte match, logical-object accuracy and unsupported “delivered version” assertions. Fail when a content hash is mistaken for object identity or first-seen bytes for historical delivery bytes |
| **H3: Progressive reads improve efficiency without hiding necessary evidence** | One-shot full transcript, bounded snippet search plus expansion, and catalog-led discovery; match source availability and total budget | Success versus tokens read, calls and latency. Include Cass/AgentsView-style progressive retrieval, not only a weak top-k baseline. Falsified if the same benefits follow from generic search/read tooling |
| **H4: Explicit unknowns plus raw fallback improve calibration** | Remove source files, hide event classes, truncate streams and change roles while keeping parse counts stable. Ablate coverage notices and fallback separately | False absence/completeness claims, evidence recovery, abstention accuracy and unnecessary abstentions. Merely printing “unknown” is not success if downstream choices remain wrong |
| **H5: Artifact packaging helps transfer to another agent** | Fresh consumers receive equal-budget raw history, existing cited packs, or artifact records. Separate harness transfer from model-backbone transfer | Correct artifact/version choice and a small executable continuation check. Falsified if advantage disappears after matching evidence/byte availability and instructions |
| **H6: Agent-assisted adapter repair reduces total maintenance cost** | Historical release-shaped changes with held-out semantics; compare manual repair and assisted repair under the same oracle | Human review time, patch correctness, missed semantic drift and false alarms. Falsified if syntactic repair saves coding time but increases review or silent errors |

Do not define ground truth as “whatever the current gate admits.” Ask annotators independently whether the user was handed an artifact, which object it was, what evidence supports that interpretation, and whether bytes are knowable. Record disagreement and ambiguous cases. Include genuine deliverables with no final path, cited source files, drafts, rejected outputs, examples, canceled turns, subagent results and multilingual wording.

Report extraction, retrieval, evidence validity, artifact recovery and downstream behavior separately. A catalog can retrieve the right declaration while being unable to recover the bytes. A source pointer can resolve while the cited text fails to support the claim. An answered task can be correct by chance despite invalid evidence.

Freeze corpus hashes, source snapshots, parser/index builds, annotation version, ranking and tie order. Use scenario-clustered uncertainty estimates, per-family results and paired comparisons; for model consumers, repeat with fixed model/prompt settings and retain failed runs. Report ingestion/storage cost as well as query cost. Snapshot preservation must be its own ablation: giving only one condition extra historical bytes confounds storage with retrieval design.

## What maintenance evidence actually supports

[Migrating Code At Scale With LLMs At Google](https://arxiv.org/html/2504.09691v1), read at §3.3 and the discussion, supports the practicality of assisted code changes combined with parsing, build/test validation and human review. It is a specialized migration case study, not evidence that autonomous agents detect semantic changes in undocumented log formats.

[A Large-Scale Evaluation for Log Parsing Techniques: How Far Are We?](https://arxiv.org/abs/2308.10828), abstract-level evidence, and the [Loghub repository](https://github.com/logpai/loghub) motivate measuring rare events and template-balanced quality rather than aggregate parse totals. They evaluate system-log parsing, not the meaning of agent delivery declarations. No directly matching evaluation of agent-generated local-log adapters under silent semantic drift was verified in this round.

A useful mutation set must distinguish: harmless extra fields; renamed required fields; record reordering/duplication; changed actor/audience; identical-shaped records whose meaning changes; omitted attachments; and success-shaped calls with failed or absent results. Schema fingerprints catch some structural changes, fixtures cover only their cases, and stable counts can coexist with systematic semantic omissions. These are limitations of the measurement, not evidence that drift is undetectable.

## Questions for Opus and the user

1. What exactly is an “assistant-facing delivery declaration”: a final response to the user, a tool return to an assistant, a subagent handoff, or a declared protocol artifact? Which audience and event boundary is the ground truth?
2. Is the target benefit finding work, selecting the correct bytes, understanding why it was delivered, or enabling continuation? Which is the primary falsifiable claim?
3. Is a gate an inventory definition or only a retrieval prior? How are useful artifacts without declarations handled without redefining the benchmark to exclude them?
4. What establishes logical object identity across rename, copy, regeneration and replacement? Which relations may remain ambiguous?
5. When first observation is late, should the answer be “declaration found, historical bytes unknown”? What independent evidence could legitimately strengthen that statement?
6. Which baseline is the real bar: Cass packs, AgentsView revision-bound retrieval, Obelisk evidence queries, or generic search plus filesystem access? What extra information does each receive?
7. What fraction of maintenance effort concerns detecting changed semantics rather than writing adapter code? Which public historical releases can support a held-out test?
8. What would make the direction not worth pursuing—for example, no advantage after controlling for snapshots, or admission recall too low for real handoff tasks?

No publication, public branch, commit, private-log access, credentials, paid model trial or implementation change was performed. A later public report still needs the pending user approval; this research round itself is complete.
