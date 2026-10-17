# Search and access log

Date: 2026-10-17 UTC. Independent public related-work review; not a systematic review or proof that other prior art is absent.

## Workspace and boundaries

All work is under `/workspace/gleaner-novelty-review/`; Praxis is unchanged. No root AGENTS.md was found. No private logs, credentials, builds, model trials, commits, pushes, PR edits or publication. PR #4 is outside scope; public-report approval remains pending. Later authorized commits require GPT Task <gpt-task@example.invalid> as author and committer.

## Pinned repositories

| Repository | HEAD read | Inspected scope |
|---|---|---|
| [lesPrivilege/gleaner](https://github.com/lesPrivilege/gleaner) | `22dd07d926a764f0a2efcdeb093b78f0b9eab41b` | README only for current product grounding; no implementation audit |
| [Dicklesworthstone/coding_agent_session_search](https://github.com/Dicklesworthstone/coding_agent_session_search) | `6bc477a97dc6b0b55f3019753adf5860a2713b8e` | README, selected `src/search/pack_planner.rs`, CLI call-site search in `src/lib.rs`; no execution |
| [kenn-io/agentsview](https://github.com/kenn-io/agentsview) | `33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d` | README, `docs/mcp.md`, artifact-sync and two memory-verification documents, selected `internal/mcp/tools.go` field definitions |
| [tommy0103/obelisk](https://github.com/tommy0103/obelisk) | `a4b7329e1fcb8d907ec1f1c9543a26513d87631c` | README and `skill-doc/references/retrieval-semantics.md`; documentation, not runtime verification |
| [getzep/graphiti](https://github.com/getzep/graphiti) | `d50741d1bf463cbe3859eb73914cbff1b66839e6` | Selected `graphiti_core/graphiti.py`, `nodes.py`, `edges.py`; retention option, episode content and source/temporal fields |

Clones are in `sources/{gleaner,cass,agentsview,obelisk,graphiti}`. SHAs pin examined snapshots, not first feature introductions.

## Exact search strings by batch

Web search snippets were discovery leads. Capability claims use primary papers, official documentation or original code, not third-party summaries or social posts.

1. Initial memory/local-tool search (`initial_1.json`):
   - `MemGPT Towards LLMs as Operating Systems arxiv Letta recall memory archival memory`
   - `A-MEM Agentic Memory for LLM Agents paper github`
   - `Zep temporal knowledge graph architecture agent memory Graphiti paper`
   - `agentsview cass coding agent session search Obelisk agent memory local logs github`
2. Closest local competitors (`round2_1.json`):
   - `Obelisk agent session memory local logs github MCP`
   - `agentsview github wesm`
   - `coding_agent_session_search robot search expand view line_number source_path`
   - `agent memory artifact catalog delivery declaration retrospective logs provenance version retrieval`
3. Evaluation/experience discovery (`round3.json`):
   - `site.arxiv.org LongMemEval benchmark long term interactive memory 500 questions abstention`
   - `site.arxiv.org LoCoMo evaluating very long term conversational memory agents`
   - `site.arxiv.org MemoryBank LongMemEval MemoryBench agent memory benchmark experience reuse`
   - `site.arxiv.org agent trajectory memory experience retrieval ExpeL Agent Workflow Memory Memento`
4. Public product/protocol counterexamples (`docs_search.json`):
   - `site.docs.letta.com memory blocks archival recall export agent file .af`
   - `site.claude.com site.code.claude.com docs memory files auto memory local transcript JSONL`
   - `site.docs.anthropic.com memory tool client side files view insert str_replace`
   - `site.modelcontextprotocol.io specification resources resource_link structuredContent tools outputSchema`
5. Reference-driven memory expansion (`experience_search.json`):
   - `site.arxiv.org ExpeL LLM Agents Are Experiential Learners 2308.10144`
   - `site.arxiv.org AriGraph Learning Knowledge Graph World Models with Episodic Memory 2407.04363`
   - `site.arxiv.org Hindsight Building Agent Memory that Retains Recalls Reflects 2512.12818`
   - `site.arxiv.org "ReAct" "Self-RAG" retrieval`
6. Narrow artifact/progressive-retrieval expansion (`closest_extension.json`):
   - `site.arxiv.org "FileGramBench"`
   - `site.arxiv.org "ReadAgent" gist memory lookup`
   - `site.arxiv.org "Portable Agent Memory" protocol provenance 2605.11032`
   - `site.arxiv.org "adapter" "drift" "LLM" API evolution`
7. Maintenance and state-resumption search (`maintenance_docs.json`):
   - `site.arxiv.org "API" "evolution" "benchmark" LLM code migration`
   - `site.arxiv.org "log parsing" LLM evaluation unseen templates Loghub LogPub`
   - `site.anthropic.com engineering memory tool context management September 2025`
   - `site.langchain.com docs langgraph persistence checkpoints threads time travel`
8. Verification follow-up (`closing_search_1.json`):
   - `"A Large-Scale Evaluation for Log Parsing Techniques" original paper LogPub`
   - `"Migrating Code At Scale With LLMs At Google" 2025 human review`
   - `"Portable Agent Memory" "pam-sdk" github Ravindran`
   - `site.arxiv.org "ALCE" "Enabling Large Language Models to Generate Text with Citations"`

## Paper access depth

Full HTML was accessible through the web tool; only the listed passages were read, not every appendix or reference.

| Paper/version | Passages used |
|---|---|
| MemGPT `2310.08560v2` | memory/control-flow description; DMR, document QA and nested KV evaluation |
| A-Mem `2502.12110v11` | §3 note/link/evolution/retrieval; §4.1–4.2 dataset and setup |
| Zep `2501.13956v1` | §2 episodic/semantic graph, source links and temporal invalidation |
| Hindsight `2512.12818v1` | §3–4 representation/retention; code-availability statement |
| ReadAgent `2402.09727v3` | overview, gist/page lookup and relevant §3 passages |
| A-RAG `2602.03442v1` | §3 interface/loop, §4 task description; displayed date differs from nominal identifier chronology, so no first-date claim inferred |
| ExpeL `2308.10144v2` | overview/figure and introduction; not complete methods audit |
| AWM `2409.07429v1` | §2 offline/online workflow induction and success gate; §3 benchmark description |
| MemOS `2505.22101v1` | short-version §4 conceptual metadata/lifecycle/provenance/migration |
| Portable Agent Memory `2605.11032v1` | §§3–5 schema/provenance/transfer, SDK claims and limited pilot |
| LongMemEval `2410.10813v2` | overview, task/design choices and evaluation framing |
| LongMemEval-V2 `2605.12493v1` | §3 context-gathering protocol, §4.2 AgentRunbook-C; official project and code/data links |
| MemoryAgentBench `2507.05257v1` | competency definitions and incremental-construction overview |
| FileGram `2604.04901v1` | §§3–5 actions/content deltas, evaluation and memory framework |
| Google code migration `2504.09691v1` | §3.3 validation; discussion and validity limits |

Abstract/project/repository depth only: AriGraph `2407.04363`; LoCoMo `2402.17753` and its released dataset README; ALCE `2305.14627v2`; large-scale log parsing `2308.10828` and Loghub. MemoryBench, LoCoMo-Plus, MemBench, MemP, Memento and other discovery hits were not promoted to detailed comparisons without sufficient inspection. This is a scope limit, not a quality judgment.

Official contract passages inspected: Letta AgentFile (legacy V1 page), Anthropic memory-tool operations/client-side storage, AgentsView/Obelisk/Cass documents above, MCP 2025-06-18 structured output/resources, A2A artifact fields/examples, LangGraph persistence/time-travel descriptions, and W3C PROV-DM revision/entity relations. The PROV check was intentionally narrow because a separate stream covers provenance reconstruction.

## Access failures and unresolved verification

- Shell HTTP requests for 15 arXiv HTML pages failed with `Tunnel connection failed: 403 Forbidden`. No bypass or escalation was attempted; the web tool supplied the public text. The failed downloader and `sources/papers/manifest.json` preserve those outcomes. They are not successful full-text snapshots.
- `bs4` was unavailable. A standard-library extraction helper was written, but arXiv transport failed before extraction. No dependency install was required.
- Two LongMemEval-V2 link clicks using a URL instead of the returned page reference failed with invalid arguments. Retrying with the proper reference succeeded for the official GitHub repo and Hugging Face dataset.
- A search for `cleanupPeriodDays` on the current Claude settings page returned no match. No retention-duration claim in the report relies on it.
- Portable Agent Memory's claimed SDK/test suite was not independently verified. The report treats the paper's transfer results as author-reported pilot evidence, not reproduced facts or a verified implementation.
- No directly matching study of agent-generated log adapters detecting silent semantic drift was verified. Code-migration and general log-parsing evidence is explicitly adjacent.

Raw web-tool response records are retained in `sources/web-results/`; these include search output and accessed passages, not necessarily complete webpage snapshots. Read-only clone inspection was done with `rg`/`sed`. The Markdown files are the deliverables; source caches support audit. No remaining access blocker prevents this bounded review, but no empirical efficacy claim has been established.

Coordinator-supplied provenance leads, not independently read or used as evidence here: [YesWorkflow](https://www.usenix.org/system/files/tapp15-mcphillips.pdf) and [Git2PROV](https://ceur-ws.org/Vol-1035/iswc2013_demo_32.pdf). A companion stream covers them. The coordinator also reported a 26-task benchmark pilot and a 2×2 design separating indexing benefit from newly captured state; those artifacts were not audited here.
