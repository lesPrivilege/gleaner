# Process log — separate from the research report

Date: 2026-10-17 UTC. Scope: retrospective read-only provenance reconstruction and governance for Gleaner, with later generalization gated on a real second domain.

## Authorization and isolation

The delegated user request authorized deep public research, isolated local deliverables and separate proposal registration. It excluded product edits, deployment, public push, private logs and credentials. The provisioned Praxis directory was left unchanged. Initial workspace discovery listed AGENTS.md paths; it did not open Praxis content or logs. No applicable AGENTS.md existed at `/workspace` for this isolated directory.

Work root: `/workspace/gleaner-provenance-research-2026-10-17`. All authored files, source snapshots and synthetic test writes were confined here. Synthetic temporary files and a Git object database were created beneath `probes/` and removed by the runner. No Git commit was made.

The environment started successfully. After a later environment-disconnected notification, a read/write check succeeded and found 60 already saved files totaling 2,092,395 bytes at that checkpoint. Work was preserved and continued. `environment-check.txt` records that check.

## Search and verification

Applied the available Exa Search skill and read its searching, source-quality, synthesis and paper-query guidance. The subsequent cloud-skill availability update did not require restarting completed research. No subagents were spawned. A separate researcher was assigned memory-system nearest-neighbor comparisons; those stayed outside this stream.

Ran 20 Exa discovery queries requesting 99 result slots across six themes: counterexamples, execution capture/replay, standards/catalogs, linkage/schema evolution, provider storage, and governance. Requests overlap and include irrelevant results. `search-workstreams.json` records angles and counts. Original PDFs, author/institutional pages, official specifications and pinned source files were preferred over commentary.

Explicitly searched counterexamples to the prospective-instrumentation claim. Accepted prior-art anchors include Deolalikar/Laffitte 2009, Magliacane 2012, Git2PROV 2013, YesWorkflow 2015 and Blount et al. 2021. Runtime collectors were distinguished from post-hoc inference. A broad CURATE query returned unrelated causal-discovery work; it was not used as provenance prior art. Community GitHub issues were discovery leads only, not provider guarantees.

Bibliographic and access details were checked through source headers/extracted text, with exact original links retained. Some tools return selected or truncated page extracts; “public full text” in the atlas refers to access availability, not a claim to have closely read every page. Methods and limits were examined; experiments in papers were not replicated. The atlas labels partial access/verification, including PROV-CONSTRAINTS, Lamport PDF extraction, and publisher access for the sanitization paper.

## Access failures and safe alternatives

- Direct Python requests to public GitHub API endpoints failed with proxy tunnel `403 Forbidden`; the web reader also could not open those API URLs. No bypass or credential lookup was attempted. The available GitHub connector successfully read the same public repository, PR and source files.
- Two early GitHub calls used incorrect argument names and returned argument-binding errors, with no operation executed. Public `github_fetch` and correctly parameterized PR metadata reads succeeded.
- Guessed historical Codex paths under `core/src/rollout` and `tasks/ghost_snapshot.rs` returned 404. Public pinned repository listings located current rollout and message-history crates. Failure responses remain under `process/failed-path-*.json`.
- A direct PREMIS PDF web fetch returned 403; Exa provided public text from the original Library of Congress URL. The report states this difference.
- OpenAI configuration documentation redirected to ChatGPT Learn. Pinned source code was used to qualify broad history-persistence wording.
- No auto-review approval rejection occurred. No action is pending or uncertain because of a tool mutation: all external calls were read-only.

## Repository/source verification

Gleaner main: `22dd07d926a764f0a2efcdeb093b78f0b9eab41b`; tree `ea7c7e601be4f5a178159964028500d501d590c4`. PR #4 was open, not merged, with base equal to main and head `72a42993512281a8bcc36fd9c6f22566132258d9`. A merge-test SHA was not mistaken for merged history.

Inspected the pinned README, SPEC and five relevant source files: SessionLog, ClaudeCodeAdapter, CodexAdapter, Indexer and Registry. No Gleaner test/build was run. PR-reported verification was treated as an author's report, not this research's evidence.

Codex public main: `ce0323f2f2d3b25e82806cd555237da3db4e1897`. Inspected rollout recorder/policy/config/maintenance and message-history implementation. Current source shows mode-dependent event retention, output truncation in specified cases, compressed storage handling, and legacy ghost-snapshot filtering. It does not establish a universal current file-checkpoint guarantee.

Ten locally saved code files were normalized only to remove transport-added final newlines where necessary, then verified using Git blob SHA-1 against the pinned repository directory entries. Independent SHA-256 digests and lengths are in `evidence/public-source-manifest.json`.

## Synthesis and probes

Authored a minimal typed evidence model, alternatives to graph storage, feasibility matrix, bounded recipes, resolver/migration/correction analysis, permission boundaries and eight research-only proposals. All distinguish observation from assumptions and original provider state from catalog-authored state.

Ran 20 synthetic checks once after creating the fixture runner: 12 ambiguous-history pairs, three bounded transformation/inverse cases, three concrete filesystem/Git experiments, two governance data-model illustrations. All passed. No provider runtime, real log, source ACL or production reconstruction implementation was tested.

Final validation checks UTF-8 part sizes below 10,000 bytes, local Markdown targets, pinned source hashes and the saved probe summary. Report packaging excludes raw third-party retrieval extracts and public source-code copies; their original URLs and hashes remain available locally.

## Outcome and pending scope

Local research is complete. No remaining execution/filesystem blocker. Public push/publication remains pending user approval and was not attempted. External issue/proposal registration was not performed; eight proposals are separately registered in report Part 11. If a commit is later explicitly authorized, both author and committer must be `GPT Task <gpt-task@example.invalid>`.
