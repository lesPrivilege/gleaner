# Gleaner: retrospective provenance and governance research

Completed 2026-10-17 UTC. Independent future research; no v0.1 requirement or adopted lifecycle contract.

**Main finding:** useful read-only reconstruction is possible in bounded cases, but obtaining exact bytes, establishing delivery-time bytes, inferring logical identity, and approving use are separate claims. Prior work already covers post-hoc and recorder-free provenance; novelty must be positioned cautiously.

## Complete report, in parts under 10,000 UTF-8 bytes

| Part | Contents |
|---|---|
| [1. Findings and scope](research/01-findings-and-scope.md) | Conclusions, public Gleaner pin, existing implementation seams, now/later/unsupported |
| [2. Reconstruction paper atlas](research/02-paper-atlas.md) | Exact original sources for legacy inference, Git2PROV, YesWorkflow, possible provenance, PASS, noWorkflow, ReproZip |
| [2b. Linkage and semantics paper atlas](research/02b-linkage-and-semantics-atlas.md) | Record linkage, schema matching, why/where provenance, semirings, ordering, sanitization |
| [3. Standards and implementation atlas](research/03-standards-and-implementation-atlas.md) | PROV, OpenLineage, catalogs, preservation, event sourcing, schema evolution, Git/watchers |
| [4. Public provider evidence](research/04-provider-evidence.md) | Documented Claude/Gemini checkpoints and assets; pinned Codex persistence code; exact verification limits |
| [5. Minimal model](research/05-minimal-model.md) | Evidence categories, natural units, domain adapters, separate persistence and storage alternatives |
| [6. Reconstruction feasibility](research/06-reconstruction-feasibility.md) | Exact requirements for byte recovery, delivery binding, derivative edges and abstention |
| [7. Bounded recipes](research/07-bounded-recipes.md) | Read-only Git/snapshot/edit recovery, reverse reconstruction and candidate-only fallback |
| [8. Adversarial probes](research/08-adversarial-probes.md) | Executed synthetic checks, proposed integration scenarios, evaluation protocol |
| [9. Pointers and evolution](research/09-pointers-and-evolution.md) | Resolver semantics, staleness, evidence addressing, schema migrations and corrections |
| [10. Permission boundaries](research/10-permission-boundaries.md) | Personal-local vs enterprise metadata/evidence access, revocation, snapshots and disclosure |
| [11. Proposals and Opus handoff](research/11-proposals-and-opus-handoff.md) | Eight separately registered research proposals; concise now/later/unsupported handoff |

The atlas covers 14 papers and 20 standard/implementation entries, plus provider documentation and pinned public code. Discovery used 20 Exa queries requesting 99 result slots across six themes, followed by original-source reads and additional web/GitHub verification. Result slots include duplicates and irrelevant leads; they are not 99 distinct papers read.

## Supporting evidence

- [Synthetic probe runner](probes/run_probes.py) and [results](probes/results.json): **20 passed, 0 failed**. No production/provider behavior or real-user recovery rate was validated.
- [Public revision pins](evidence/revision-pins.json): Gleaner main `22dd07d926a764f0a2efcdeb093b78f0b9eab41b`; PR #4 open/unmerged at head `72a42993512281a8bcc36fd9c6f22566132258d9` when read.
- [Public-source manifest](evidence/public-source-manifest.json): ten downloaded source files independently match their pinned Git blob IDs; local SHA-256 and byte lengths are recorded.
- [Validation results](evidence/validation.json): part sizes, local links, source hashes and probe-result checks.
- [Separate process log](process/PROCESS.md) and [search workstreams](process/search-workstreams.json).

`public-source/` holds selective public source-code snapshots. `process/` also retains tool retrieval responses and failures for traceability. Those raw third-party extracts are not part of the report bundle. The bundle contains the authored report, synthetic probes, evidence manifests and concise process records; original links remain in the report.

## Scope and limits

No Praxis or Gleaner workspace/product files were modified; no private logs or credentials were accessed. Public Gleaner source was inspected read-only. No public push, commit, deployment or external proposal registration occurred during the originating research. The environment was checked after a disconnect notification and remained usable. Public GitHub was read through the connector after direct API transport failed.

Provider capability is documented, not demonstrated on a user's session. Exact reconstruction may remain impossible when bases, assets, outcomes, identity or delivery bindings are missing. There is no remaining blocker to this local research deliverable. Publication remains pending user approval. A later explicitly authorized commit must use `GPT Task <gpt-task@example.invalid>` as both author and committer.
