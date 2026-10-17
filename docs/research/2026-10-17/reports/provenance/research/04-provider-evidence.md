# 4. Public provider logs and checkpoints

Checked 2026-10-17. Documentation describes capabilities; it does not establish that a particular user's session enabled them, retained them, or used the same version. No private logs, configuration, credentials, hidden account endpoints, or checkpoint directories were accessed. No restore command was run.

## Claude Code

[Checkpointing documentation](https://code.claude.com/docs/en/checkpointing) says checkpoints precede turn-starting prompts, track the file-editing tools, retain snapshots for the 100 most recent checkpoints, and normally sweep old snapshots after roughly 30 days subject to `cleanupPeriodDays`. It explicitly excludes Bash changes, limits external/concurrent edits, distinguishes subagent cases, and documents link-related restore exclusions. This supplies existence and retention evidence, but not a promise that every intermediate or delivery-time version is captured.

[Application-directory documentation](https://code.claude.com/docs/en/claude-directory) identifies:

| Documented location under the configured Claude data root | Evidence potentially available |
|---|---|
| `projects/<project>/<session>.jsonl` | Messages, tool calls, and tool results |
| Session `subagents/` | Separate subagent transcripts |
| Session `tool-results/` | Spilled large tool outputs and full-size MCP-returned images |
| `file-history/<session>/` | Pre-edit snapshots used by checkpoint restore |

The default root is `~/.claude`, overridable by `CLAUDE_CONFIG_DIR`. The documentation describes a retention sweep and exceptions, including version/configuration-dependent Desktop behavior. A directory's documented location is not proof of its present contents. Binary assets may survive in documented tool-result storage even when inline display was reduced. Acquire only authorized specific records/assets, without sweeping unrelated sessions.

[Agent SDK file-checkpointing documentation](https://code.claude.com/docs/en/agent-sdk/file-checkpointing) separately documents enabling checkpointing, checkpoint UUIDs, and Write/Edit/NotebookEdit coverage. SDK options and CLI defaults are different interfaces. An SDK rewind modifies files, so a research reconstructor should read a copied snapshot through a documented/exported mechanism instead of rewinding a live project. The exact manifest-to-file mapping must be validated for the session version; this study did not inspect an actual manifest.

## Codex: pin implementation rather than infer from old paths

Public repository main inspected at **ce0323f2f2d3b25e82806cd555237da3db4e1897**, commit timestamp 2026-10-17T04:02:21Z. These are source observations at that SHA, not a claim about the version installed on a user's computer.

| Pinned source | Evidence observed | Consequence |
|---|---|---|
| [rollout/src/recorder.rs](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/rollout/src/recorder.rs) | JSONL rollout persistence, session paths under the configured Codex home, deferred file creation until persistence, compressed-rollout handling | A live UI event need not already be durable; a plain JSONL-only scanner can miss supported storage forms |
| [rollout/src/policy.rs](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/rollout/src/policy.rs) | Persistence differs by legacy/paginated history mode; paginated command aggregated output and MCP results have 64 KiB persistence budgets; many event variants are transient | Inspect the persisted record variant and truncation markers. Do not apply the 64 KiB observation as a universal limit on every response item or provider |
| [message-history/src/lib.rs](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/message-history/src/lib.rs) | `history.jsonl` entries contain session ID, timestamp, and text; settings can disable or cap this history | This history file is not itself a full filesystem or tool-execution journal |
| [rollout/src/maintenance.rs](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/rollout/src/maintenance.rs) | Compression and migration publish replacement files by rename | Path/line alone is insufficient evidence identity across storage migration |

The recorder also explicitly recognizes and strips legacy `ghost_snapshot` records while loading history. That is evidence of legacy-format handling, **not** evidence that today's session has recoverable checkpoints, where their blobs live, or how long they persist. No current universal Codex file-checkpoint existence/location/retention guarantee was established. Historical snapshot recovery must be scoped to a verified old version and actual surviving objects.

The [official configuration reference](https://developers.openai.com/codex/config-reference/) redirected to a ChatGPT Learn URL during retrieval and broadly describes history persistence. The narrower source distinction above prevents interpreting that wording as proof of full tool or file retention. Old guessed `core/src/rollout/...` paths returned 404; the current files were located under the `rollout` crate and preserved locally. Community issue reports were discovery leads only, not authoritative retention evidence.

## Gemini CLI: a documented comparison, not a second product domain

[Checkpointing docs](https://geminicli.com/docs/cli/checkpointing/) describe an opt-in feature, disabled by default, creating a shadow Git snapshot before an approved modifying tool. They identify `~/.gemini/history/<project_hash>` for the shadow repository and typically `~/.gemini/tmp/<project_hash>/checkpoints` for JSON conversation/tool-call metadata. These are pre-operation snapshots; a checkpoint does not itself prove the pending tool ran. The page did not establish an indefinite checkpoint retention guarantee.

[Session management docs](https://geminicli.com/docs/cli/session-management/) separately describe automatic conversation/tool input/output storage under project-scoped `~/.gemini/tmp/<project_hash>/chats/`. Chat-save checkpoints, filesystem snapshots and automatic transcripts are different objects. A public documentation claim of complete project state still requires checking inclusion/ignore rules and the actual snapshot's tree before asserting a particular file or binary is present.

## Read-only acquisition conditions

Before using any provider evidence in a future authorized experiment, record provider/version/configuration, source-root scope, session/branch identity, retention policy as observed, completeness flags, and whether large payloads were externalized. Resolve explicit references; do not guess a private path then treat an empty result as “never existed.” Preserve both recorded event time and acquisition time.

Never invoke a provider's `/restore`, `/rewind`, or analogous API on the user's worktree merely to inspect history. Obtain an authorized copy/export and read it independently. If exact bytes require an unavailable manifest, missing attachment, undocumented internal lookup, or retention-expired snapshot, report that specific gap and retain the candidate.

Text is not inherently recoverable: a partial read, a missing patch base or normalized transcript may lose bytes. Binary is not inherently unrecoverable: a complete encoded asset, Git blob, externalized tool result or retained snapshot may provide exact bytes. Capability must be determined per representation, not per file extension.
