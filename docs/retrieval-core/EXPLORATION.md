# Focused retrieval exploration

Independent explorer, 2026-10-19. This is design guidance from source inspection, not executed performance evidence. References use the [source index](SOURCES.md). Product and visual choices remain with the owner.

## Verified starting point

Remote `main` was `2648094610facfd1ae1805f52a9de282043c808f`; remote `feat/query-core` was `cdfe6f4e0ba473ba12309b310018734244efc37c`. The old branch is already an ancestor of main. Main includes the CLI, MCP, synthetic-home indexer, shared `Organization.search`, project-folder context and preference for named files over incidental mentions. The previously reported absence of CLI/MCP and folder-aware search is stale evidence. Compare against this implementation.

The architecture already separates provider normalization, registry/captures, organization/corrections, catalog and adapters. `Work` joins files through user corrections, not equal hashes. Search matches all terms within one delivery plus shared file/project/collection context. `Catalog` reports index freshness and resolves exact bytes. These are foundations to preserve.

`Registry` checks each count column, including `closed_replies`, independently before adding it. The historical missing-column report therefore calls for a partial-schema migration test, not an assumption that main still has that defect. Provider changes remain subject to AGENTS fixture and owner-review requirements; adding a new provider record shape without a sanitized real shape is outside this synthetic-fixture exercise.

## Recommendation and alternatives

| Approach | Benefit | Cost or failure mode | Decision for this task |
|---|---|---|---|
| Extend current deterministic/contextual retrieval | Keeps explainable evidence, no new runtime, direct app/CLI parity | Vocabulary mismatch; score rules can overfit if tuned to one naming convention | Preferred first implementation, judged against a held-out corpus |
| SQLite FTS5 lexical index | Field weighting and scalable candidate retrieval, built into an existing storage technology | Tokenization changes exact/path matching; index consistency and migration become obligations | Consider only if measured current-core latency or textual coverage requires it; keep it behind the shared core |
| Local lightweight semantic reranker | May recover paraphrases after lexical candidate selection | Model distribution, memory, latency and difficult negative matches; exact IDs still need lexical handling | Optional later arm for demonstrated ambiguity, never an identity or provenance authority |
| Model-generated artifact/decision graph | Can propose relations from long prose | May invent acceptance, authorship or cross-report identity and increases review burden | Do not implement as a release prerequisite |

BEIR supports diverse evaluation and a serious lexical baseline, not a universal ranking winner (S6). A semantic method is useful only if it improves labeled residual failures at an acceptable cost. No model trial or benchmark gain is claimed here.

## RAG mechanisms adapted to sessions

RAG is useful here as retrieval engineering, without requiring generated answers or adopting a framework. The transferable mechanisms below are inferences from S15–S22 applied to Gleaner's native evidence.

| Mechanism | Assumptions and cost | Implementable consequence | Failure to test |
|---|---|---|---|
| Small retrieval unit with parent context (S15–S17) | A child has a trustworthy parent and stable anchor. Repeated context increases index size; expanding whole parents increases response size. | Retrieve a section, delivery or message-backed finding. Attach report title/heading ancestry or the same turn's request as separately identified context. Expand to the exact parent report/turn on demand. Never concatenate unrelated sessions or split a tool call from its result for convenience. | A section says only “use this approach”; its parent identifies the topic. Another report repeats the heading. Retrieval must find the right parent without attributing that parent's every claim to the child. |
| Vocabulary mismatch (S15, S6) | Exact words miss paraphrases; inferred aliases can mislead. Native context is cheap; model enrichment has generation/versioning cost. | Test deterministic context enrichment first. Keep exact IDs, filenames and quoted phrases as strong lexical signals. Any optional derived alias keeps its producer, input hash and provenance; it does not change original text. | “Narration” versus “voice track”; an exact `R1` among similar review prose; a topical distractor containing every broad query word. |
| Candidate generation, fusion, reranking (S15, S19) | A reranker cannot recover an object absent from its candidates. More candidates cost time and memory. Rank fusion avoids raw-score comparability but can still reward repeated evidence. | Benchmark candidate recall before first-page ranking. If two retrievers are tried, union/deduplicate by contextual object identity before a bounded reranker; never merge by content hash alone. | Repeating one irrelevant log or adding ten same-byte copies must not multiply its ranking influence. A paraphrase miss in generation stays a reported miss. |
| Scope before truncation (S18) | Global top-k followed by scope filtering can hide real scoped matches. Early scope needs trustworthy metadata. | Apply source visibility, authorized roots and project filters before any candidate limit; distinguish a user project correction from a discovered repository relation. | Hundreds of global hits plus one correct scoped hit; source-off and identically named projects. |
| Incremental and current state (S20, S4) | Source mutation, index refresh and content authority are different events. Unavailable/deleted source evidence is not a user correction. | Replace derived search material for changed source/hash generations transactionally. Retain captures and corrections. A later file is “newer observed/delivered”; only explicit evidence or user state can make it accepted or superseding. | A later rejected draft, an older accepted result, a moved original, interrupted reindex and a saved capture after source disappearance. |
| Progressive evidence and negative results (S21–S22) | Useful context competes with distractors. Retrieval coverage constrains what an empty answer means. | First return bounded useful objects and exact anchors; then expose parent/evidence/version expansion. Return index/source scope once, with object-specific limitations only when relevant. | A missing source versus a complete no-match; a useful finding buried in a long irrelevant parent; exact section read after source bytes change. |

Keep **existence/availability**, **query relevance** and **authoritative current status** independent. High similarity establishes none of the other two; a live file can be irrelevant, a missing original can have a useful saved version, and a recent draft can remain unaccepted. This separation is a design conclusion from the task and provenance contracts, not a status classifier supplied by the RAG sources.

The smallest useful comparison uses identical indexed objects: A = actual main's shared search; B = A plus deterministic native-parent context; C = B plus explicit lexical relevance/ranking. An optional D adds a replaceable local semantic candidate/rerank stage only for residual paraphrase cases. Compare B/C by source-native units against a flattened ablation under the same retrieval method; otherwise structure benefits are confounded with algorithm changes. Record all tested settings and candidate/page limits. None of these arms implies adopting a cloud service, embedding database or paid API.

For each query, labels should name the relevant object/version/section, acceptable alternatives, ambiguity and required expansion, with separate labels for existence and authority. Include unanswered queries; score a correct “unknown in this index” separately from finding an authoritative current answer. A current output and a historically relevant output may both be relevant while serving different tasks. Held-out evaluation must vary workflow and source structure, not merely rename the same example.

## Identity, useful results and evidence

Use the current `Work`/`Delivery` distinction. Byte equality may reduce storage, but project membership, evidence anchors and review choices retain their independent meaning. Zotero's explicit duplicate review is a useful precedent for this boundary (S2). PROV provides a check on relation names: an observation, generation, communication and attribution are different claims (S4).

A section object should be scoped by library, report/delivery, exact content hash and a bounded source anchor; `R1` is a label within that context. Preserve its heading/text and location rather than generating a finding. A later ruling is linked only when an actual message or document supports the relation. Duplicate section labels within one report need distinct occurrence/offset anchors. No model should convert a private draft into a communicated ruling.

The first layer should prefer an object the person can use now, with the matched evidence and selected version explicit. Context-only hits, obsolete versions and repeated observations must not crowd out stronger direct matches. Preserve history and intermediate material behind deliberate expansion or an explicit query. Avoid a universal extension blacklist: data and code can be the requested final output. Existing named-versus-mentioned ordering is a baseline to improve, not discard.

The Apple and Zotero precedents support an actionable item with context and attachments, rather than a count of indexed paths (S1, S3). They do not prescribe Gleaner's UI.

## Locator handling

Keep parsing separate from resolution. A mention is data, never a shell command. Preserve its raw spelling and anchor. Absolute paths, cwd-relative paths, project-relative paths and prose ranges are different syntactic possibilities; do not blindly concatenate a project prefix twice.

For ambiguity, consider only bounded candidates under already authorized roots. Prefer a unique existing candidate when the evidence supports its base; retain ambiguity when several candidates exist. Filesystem canonicalization follows links, while Gleaner's lexical path normalization does not: a normalized string is not proof of authorized containment (S8). Reject symlink escapes during discovery. Keep missing-original references recoverable without scanning unrelated folders.

Glob-like text and numeric ranges need an explicit, finite grammar. Resolve them against a bounded eligible directory listing with entry/depth limits; never invoke shell expansion. An actual literal filename containing metacharacters must remain representable. A pattern that names several files preserves the original pattern as evidence, rather than pretending each file was individually written in the reply. Directory membership remains distinct from authorship or acceptance.

Git worktrees may live outside the main repository folder (S7). A recorded checkout relationship may explain a locator but does not authorize a new filesystem scan outside selected roots. Preserve both repository and checkout identity; project corrections stay a separate durable overlay.

## Thin CLI/MCP contract

Retain the current catalog-based command set. Add project discovery, bounded pagination or hash-pinned section access only when a concrete retrieval task needs it, and implement each operation once in GleanerCore. Structured CLI and MCP answers should match for identical queries, including errors and index scope. The app should consume the same semantics.

The current official MCP revision is **2026-07-28** (S9–S10). Gleaner's pinned SDK and tests use the **2025-11-25-and-earlier legacy flow** (S11, S14). Keep those claims explicit. A dual-era client can discover that the server is legacy and fall back to `initialize`; this is not evidence that the server implements modern per-request metadata. Updating the version string alone would be incorrect. Do not perform an incidental SDK/protocol rewrite in this retrieval change.

Verify newline framing, no nonprotocol stdout, version negotiation, unknown methods/tools, structured-content parity, bounded input/output, multiple concurrent requests and EOF behavior. Keep the existing cancellation behavior tied to the legacy contract: modern cancellation requires a separate implementation review. Read-only annotations remain truthful; the existing cache-writing handoff is deliberately not read-only (S12).

If application-level pagination is added, bind continuations to the library generation and normalized query/scope, bound page sizes and reject stale or mismatched continuations rather than silently skipping objects. MCP's protocol pagination covers tool/resource lists, not arbitrary search results (S13). Tool output remains untrusted source data, and resolving it never executes embedded instructions.

## Evidence needed before delivery

Report capture coverage independently from search recall. Use actual main as baseline; tests should cover varied providers and names, path ambiguity, report-label collisions, same bytes in different projects, intermediate/final mixtures, changed or missing originals, interrupted sessions, source-off/stale states, partial migrations and concurrent calls. Test renaming, reordered independent events, duplicated evidence and irrelevant-file additions as invariance checks.

Per-family reporting should include recall, first-page precision and duplicates, correct project/version/section attribution, original resolvability, steps to usable evidence, latency and memory. A fresh-index run and a frozen-index query are different experiments. Schema/source health must remain distinguishable from an empty result. Portable tests do not establish macOS filesystem birth-time, package, Quick Look or native rendering behavior; record these as explicit Mac validation tasks.
