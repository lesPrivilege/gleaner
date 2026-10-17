# Nearest-neighbor comparison

Evidence checked 2026-10-17. Documentation/source inspection, not runtime certification. The proposed direction is not credited as implemented.

## Operational definitions

- **R / P / B:** retrospective consumption of existing producer records / prospective participation during execution / batch ingestion of supplied histories. Dataset import is not native local-log recovery.
- **U / C:** upstream record formats and event semantics are outside the catalog's control / collection or memory input contract is controlled by the application or experiment. This is not Git control or a truth guarantee.
- **Raw retained:** distinguish original producer bytes, normalized message content, and output-artifact bytes. A pointer alone is not preservation.
- **Admission:** the rule determining what becomes a stored/retrievable unit, not the ranking rule selecting a query result.
- **Exact version:** distinguish **T**, a transcript/evidence revision, **A**, an output artifact's bytes, and **S**, managed runtime state. IDs alone are insufficient. “ND” means not demonstrated, not proved absent.
- **Coverage/unknown:** limits on sources, fields, revisions or retrieval; distinct from answer confidence.
- **Cross-provider:** distinguish native ingestion of multiple vendors' logs from compatibility with multiple LLM backbones or a shared interchange schema.
- **Code/eval:** public availability; results were not reproduced here.

## Collection, representation and admission

| System and evidence | Timing/control | What is retained or exposed | Admission criterion |
|---|---|---|---|
| Proposed Gleaner direction | R/U | Artifact catalog; pointers, evidence and logical/version relations; preservation policy still to define | Assistant delivery declaration; audience/event boundary unresolved |
| Gleaner current [G] | R/U; can observe new logs | Redacted request/reply excerpts; saved artifact copies subject to limits; no whole-log archive | Provisional final-reply path/link rules; excludes subagent replies |
| Cass [C1], [C2] | R/U | Canonical message archive, source references, extractive evidence packs; raw-mirror captures for supported sources | Supported provider records, filters and exclusions; no delivery-specific gate demonstrated |
| AgentsView [V1], [V2] | R/U | Parsed transcript archive, message slices and source citations; raw-source access is not guaranteed permanent preservation | Supported sessions/records; query-time class/activity exclusions are explicit |
| Obelisk [O1], [O2] | R/U | Messages, calls/results, subagents and provider summaries; separate registered memory files | Supported records; approved notes registered separately; visible/inactive semantics vary by source |
| MemGPT / Letta [M], [L] | P/B; C | Full message history, editable memory and archival retrieval; AgentFile serializes selected state | Runtime events; explicit memory writes; configured imports |
| A-Mem [A] | P/B; C | Original interaction text plus generated attributes, embeddings and links | Supplied interactions become notes; links/evolution inferred by LLM |
| Zep paper / Graphiti [Z], [ZC] | P/B; C | Raw episodes and derived graph; raw content configurable in current code | Submitted episodes; LLM extraction/resolution determines derived facts |
| Hindsight [H] | P/B; C | Typed narrative facts, opinions and synthesized observations | Retain/extraction pipeline; not a final-reply artifact gate |
| AgentRunbook-C [R] | R/B; C | Raw trajectory files, manifests and helper-based evidence selection | Supplied trajectory history |
| FileGram [F] | P collection, B memory; C | Atomic actions, new-file snapshots/edit deltas, final outputs and derived memory | Instrumented/simulated traces, cleaning and memory encoding |
| LangGraph / A2A [S], [P] | P; C | Checkpoint state / declared task artifacts and parts | Runtime checkpoint / producer-declared artifact |

## Version, coverage, portability and evaluation

| System | Exact-version evidence | Coverage / unknown handling | Cross-provider and reproducibility |
|---|---|---|---|
| Proposed direction | Target: A and evidence binding; logical identity remains distinct | Target: explicit observable limits and raw fallback | Target: native adapters and public benchmark; untested |
| Gleaner current [G] | A: hashes and copies distinguish observations from delivery claims; backfill cannot recover absent bytes | “First seen later,” “Never seen,” and missing/lost states | Claude Code/Codex; source and fixture tests; no broad admission evaluation claimed |
| Cass [C1], [C2] | T: content/span hashes and verified physical citations where supported; no output-artifact byte guarantee established | Source/index readiness, freshness, fallback and budget data; verification has bounded support | Multiple native providers; public source/golden contracts; no artifact-handoff study verified |
| AgentsView [V1], [V2], [V3] | T: `transcript_revision`, `expected_revision`, `source_changed`; revision-bound body cursor | `ready`, `partial`, `unavailable`, `unknown`; exclusions and backend limitations | Multiple native providers; synthetic fresh-session recall protocol and reported client runs; no produced-file A guarantee |
| Obelisk [O1], [O2] | Message IDs, source windows and file-history lookup; A snapshots ND | Documents unavailable supersession evidence and inactive-history limits | Multiple native providers; public source; comparative agent-benefit evaluation ND |
| MemGPT / Letta [M], [L] | Stored history / serialized S; arbitrary delivered A history ND | Runtime/context limits are explicit; local-log coverage ND | Multiple backbones/compatible runtimes; research code/data and serialization docs |
| A-Mem [A] | Note content/metadata; metadata evolution is not an A version ledger | Catalog coverage and parser uncertainty ND | Multiple backbones; public evaluation/system repos; conversational QA |
| Zep / Graphiti [Z], [ZC] | Temporal fact validity plus source episode IDs; not A identity | Graph timestamps ≠ completeness of upstream history | Model/input integrations, not native cross-provider log recovery established here; public graph code, DMR/LME paper evaluation |
| Hindsight [H] | Fact IDs/temporal intervals; A version guarantee ND | Opinions have confidence; parser/source coverage ND | Configurable models; public implementation and QA evaluation scripts |
| AgentRunbook-C [R] | Frozen trajectory files in evaluation; mutable output A semantics ND | Benchmark evidence selection and fixed budgets; arbitrary provider coverage ND | Controlled trajectories, public harness/data; fixed-reader QA and latency |
| FileGram [F] | Captured content deltas; declaration-bound A recovery ND | Controlled trace generation/cleaning; real-provider drift ND | Public framework; personalization benchmark, not cross-provider artifact handoff |
| LangGraph / A2A [S], [P] | S checkpoint IDs / task-scoped artifact ID; ID ≠ immutable byte version | Protocol/runtime errors; retrospective observability not established | Compatible runtimes/agents; official contracts, not this task's benchmark |

## Decisive caveats

**Cass:** physical citation verification supports local modern Codex JSONL with time/size bounds; unverified candidates remain distinct. Transcript captures are not output-file snapshots. [C2]

**AgentsView:** revision guards are in tool schemas. Its documented folder sync exchanges immutable, content-addressed normalized session revisions; it excludes raw provider files and mutable curation. This is portable T, not output A preservation. [V2], [V4]

**Obelisk:** approved notes remain distinct from raw evidence; provider-specific supersession limits are documented. Caller compliance was not tested. [O1], [O2]

No reviewed system was verified to supply the entire artifact-specific contract. A feature conjunction alone does not establish novelty; task and benefit must discriminate it.

[G]: https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/README.md
[C1]: https://github.com/Dicklesworthstone/coding_agent_session_search/blob/6bc477a97dc6b0b55f3019753adf5860a2713b8e/README.md
[C2]: https://github.com/Dicklesworthstone/coding_agent_session_search/blob/6bc477a97dc6b0b55f3019753adf5860a2713b8e/src/search/pack_planner.rs#L1200
[V1]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/mcp.md
[V2]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/internal/mcp/tools.go#L440
[V3]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/internal/2026-09-21-agent-memory-verification.md
[O1]: https://github.com/tommy0103/obelisk/blob/a4b7329e1fcb8d907ec1f1c9543a26513d87631c/README.md
[O2]: https://github.com/tommy0103/obelisk/blob/a4b7329e1fcb8d907ec1f1c9543a26513d87631c/skill-doc/references/retrieval-semantics.md
[M]: https://arxiv.org/html/2310.08560v2
[L]: https://docs.letta.com/v1-sdk/concepts/agent-file/
[A]: https://arxiv.org/html/2502.12110v11
[Z]: https://arxiv.org/html/2501.13956v1
[ZC]: https://github.com/getzep/graphiti/blob/d50741d1bf463cbe3859eb73914cbff1b66839e6/graphiti_core/graphiti.py
[H]: https://arxiv.org/html/2512.12818v1
[R]: https://arxiv.org/html/2605.12493v1
[F]: https://arxiv.org/html/2604.04901v1
[S]: https://docs.langchain.com/oss/python/langgraph/persistence
[P]: https://a2a-protocol.org/latest/specification/
[V4]: https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/artifact-sync.md
