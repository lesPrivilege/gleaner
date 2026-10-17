# Existing evaluation datasets and protocols

Research recommendations only, 2026-10-17. No experiments below were run. This identifies tests that discriminate the novelty claim; it does not prescribe a product architecture or replace the separately assigned benchmark-design stream.

## Existing datasets and protocols

| Resource; evidence read | Reusable test or protocol | Mismatch with artifact handoff |
|---|---|---|
| [MemGPT DMR and nested KV, full-text §§3.1–3.2](https://arxiv.org/html/2310.08560v2) | Recall from earlier sessions; chained pointer-like lookup | DMR answers a fact; synthetic keys do not model renamed files, byte availability or delivery intent |
| [LoCoMo, original abstract/project](https://snap-research.github.io/locomo/) and [released repository](https://github.com/snap-research/locomo) | Long conversations, temporal/multi-hop QA, event summaries | Conversation-grounded answers, not mutable file versions. Paper collection and released subset differ; pin the actual dataset and scorer, not the name alone |
| [LongMemEval v2 paper, full-text overview/design](https://arxiv.org/html/2410.10813v2); [code/data](https://github.com/xiaowu0162/LongMemEval) | 500 questions covering extraction, multi-session/temporal reasoning, updates and abstention; retrieval and reading can be evaluated separately | Useful for correction and unknown cases, but no delivery-to-bytes relation. This paper revision is distinct from the later benchmark named LongMemEval-V2 |
| [LongMemEval-V2, full-text §3/§4.2](https://arxiv.org/html/2605.12493v1); [code](https://github.com/xiaowu0162/LongMemEval-V2); [data](https://huggingface.co/datasets/xiaowu0162/longmemeval-v2) | Insert trajectories, query compact evidence, fixed reader; 451 questions; accuracy/latency | Closest retrieval-module protocol. Environment experience QA still does not score exact delivered artifacts. Its full corpus is large; a declared diagnostic subset is not a full benchmark reproduction |
| [MemoryAgentBench, full-text overview](https://arxiv.org/html/2507.05257v1); [data card](https://huggingface.co/datasets/ai-hyz/MemoryAgentBench) | Incremental ingestion; accurate retrieval, test-time learning, long-range understanding and conflict resolution | Incremental context and synthetic fact conflicts are not provider-log drift or missing output snapshots |
| [FileGram, full-text §§3–5](https://arxiv.org/html/2604.04901v1); [framework](https://github.com/Synvo-ai/FileGram) | File actions/content deltas, profile drift, competing traces and multimodal grounding | Good event ingredients; profile reconstruction/MCQ accuracy is different from artifact identity and verified transfer |
| [ALCE, original abstract](https://arxiv.org/abs/2305.14627v2) | Separates answer correctness from citation quality | Citation support can inform claim scoring, but textual entailment does not prove a tool's external effect or an artifact's version |
| [AgentsView synthetic client verification, repository protocol](https://github.com/kenn-io/agentsview/blob/33c30f45669c3581bfb03b4bd6d64d3bd7e23f3d/docs/internal/agent-memory-verification.md) | Fresh-session recall, explicit decisions, implicit failures, corrections and current-context exceptions; require search plus source read | Very close integration protocol. It tests transcript recall, not file bytes or a general ranking advantage. Its live gate consumes model quota; it was not run here |

Do not compare headline accuracy numbers across memory papers as if they used the same task, subset, prompts, backbone, judge, retrieval budget or treatment of unanswerable cases. Published code can still require unavailable model versions or paid endpoints. For inexpensive work, publish a clearly named subset and its exact scoring rules.


Proposed discriminating tests and open questions are in [04-experiments-and-questions.md](04-experiments-and-questions.md).
