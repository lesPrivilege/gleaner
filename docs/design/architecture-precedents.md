# Architecture precedents with bounded lessons

These references support the [composition alternatives](control-panel-explorations.md), not a new implementation mandate. Gleaner's baseline is `79d724d1228a4b748572958dcbdd22aa6b7da142`. The question is how little structure can preserve useful project context, exact selection and correctable organization. Public projects below are source examples; they are not all mature interaction references or proposed dependencies.

## Mature mechanisms worth separating

| Primary reference | Mechanism established by the source | Possible Gleaner application and limit |
|---|---|---|
| [Git worktree](https://git-scm.com/docs/git-worktree) | Linked checkouts have a repository relationship independent of their ancestor directories | Use verified Git structure as affiliation evidence. It does not establish one logical project per repository. |
| [VS Code multi-root workspaces](https://code.visualstudio.com/docs/editing/workspaces/multi-root-workspaces#_workspace-file-schema) | A workspace can list multiple absolute/relative folder paths with separate display names | A collection of working locations need not dictate names or project identity. Do not import the editor's whole workspace model. |
| [Backstage descriptors](https://backstage.io/docs/features/software-catalog/descriptor-format/) | Names, namespaces, metadata and relations have explicit roles | Human identity can outlive a source location. An enterprise catalog taxonomy would be excessive for this small library. |
| [MLflow tracking](https://mlflow.org/docs/latest/ml/tracking/) | Experiments/runs, metadata and artifact storage are distinguishable | Delivery context and payload storage can remain separate. Successful execution does not establish human acceptance of an output. |

The inference for Gleaner is narrow: preserve the independent facts needed by an interaction, but do not expose each fact as a new navigation level. The [source index](source-index.md) also covers Zotero's organizational collections and Apple's selection-to-preview model.

## Pinned implementation examples

| Source at inspected revision | What the source shows | Transfer boundary |
|---|---|---|
| [Cass schema](https://github.com/Dicklesworthstone/coding_agent_session_search/blob/b605426e0d134fdc2c5621cb8c3795fb8274bfde/src/storage/sqlite.rs#L6700) — `b605426e0d134fdc2c5621cb8c3795fb8274bfde` | Separate sources, agents, path-based workspaces and conversations; provider/source context participates in conversation identity | Useful for imported-ID namespaces. Its path-based workspace is not a general logical project. Gleaner's current identifiers merit design attention; this is not evidence of an observed production collision. |
| [AgentsView mappings](https://github.com/kenn-io/agentsview/blob/905a5fe2ee7c01fb55f620d9ce4e4728aed177ae/internal/db/worktree_mappings.go#L121), [reclassification](https://github.com/kenn-io/agentsview/blob/905a5fe2ee7c01fb55f620d9ce4e4728aed177ae/internal/db/worktree_reclassification.go) — `905a5fe2ee7c01fb55f620d9ce4e4728aed177ae` | Machine-scoped path mappings, directory-boundary matching and preview tokens for applying a proposed correction | Borrow scoped, reviewable corrections; a path-prefix mapping alone cannot represent every shared or multi-repository project. |
| [Obelisk provider contract](https://github.com/tommy0103/obelisk/blob/a4b7329e1fcb8d907ec1f1c9543a26513d87631c/packages/core/src/providers/types.ts#L5) — `a4b7329e1fcb8d907ec1f1c9543a26513d87631c` | Provider-owned discovery, parsing, opaque cursors and source provenance; an indexing unit need not be a file | Keep ingestion adapters independent of presentation and future provider formats. Full transcript memory and agent execution are broader scopes than Gleaner needs. |
| Vibe Kanban [multi-repository migration](https://github.com/BloopAI/vibe-kanban/blob/d5cbb5380fa0b32e98ef9b8d987f63decce4be3a/crates/db/migrations/20251209000000_add_project_repositories.sql), [workspace/session migration](https://github.com/BloopAI/vibe-kanban/blob/d5cbb5380fa0b32e98ef9b8d987f63decce4be3a/crates/db/migrations/20251216142123_refactor_task_attempts_to_workspaces_sessions.sql), [lifecycle migration](https://github.com/BloopAI/vibe-kanban/blob/d5cbb5380fa0b32e98ef9b8d987f63decce4be3a/crates/db/migrations/20260217120312_remove_task_fk_from_workspaces.sql) — `d5cbb5380fa0b32e98ef9b8d987f63decce4be3a` | Project/repository membership, workspaces, sessions and execution processes evolve separately; task deletion is decoupled from workspace lifetime | Useful evidence against collapsing project, checkout and session. Its agent orchestration and change-review workflow do not transfer automatically. This is a historical mechanism reference, not a dependency recommendation. |
| [lcsmas/orchestra association contract](https://github.com/lcsmas/orchestra/blob/7dde445e86d5840d5cf31183dc397fd90fa5ff6a/src/main/workspaces.ts#L2381), [workspace types](https://github.com/lcsmas/orchestra/blob/7dde445e86d5840d5cf31183dc397fd90fa5ff6a/src/shared/types.ts#L80) — `7dde445e86d5840d5cf31183dc397fd90fa5ff6a` | Display-only repository association is distinct from owning a checkout or coordinating child workspaces | A personal filing choice need not change execution or source ownership. This exact repository is the reference; no broader claim about similarly named products is implied. |
| [OpenCode project identity](https://github.com/anomalyco/opencode/blob/a49f179170b620f719fc6c25986e971af47b5268/packages/core/src/project.ts#L278) — `a49f179170b620f719fc6c25986e971af47b5268` | Repository identity considers normalized remote, cached identity and root commit | An explicit repository-oriented policy can be inspected and corrected. Shared remote identity is still not sufficient to merge Gleaner's logical projects. |

These are mechanism readings, not demonstrations of those applications' rendered interfaces. No foreign application or migration was executed for this exploration.

## Three support models, only if the chosen view needs them

| Model | Minimum useful addition | When it might suffice | Cost to expose before choosing |
|---|---|---|---|
| **Affiliation overlay** | Correctable project labels/mappings over existing delivery records | Quieter project-scoped lists with occasional corrections | Names and moved source keys require reconciliation; rename/merge semantics can become awkward |
| **Explicit project catalog** | Stable project identity and accepted memberships, independent of locations | Continuing projects span repositories, provider containers and non-Git folders | Project merge/split/archive/deletion and migration become real product decisions |
| **Evidence records with project views** | Preserve claims, accepted assignments and ambiguity; derive the current grouped view | Shared work, changing cwd or conflicting mappings recur often enough to justify it | Conflict explanations and recomputation cost more; this does not require a graph database or event sourcing |

These are alternative levels of commitment, not cumulative prerequisites. None requires a Work Unit lifecycle. Ordinary path-based records and current capture selection can support a first disclosure experiment. Persistent project identity becomes useful when continuity across changed names or locations must be guaranteed.

Four synthetic checks make the choice concrete:

1. **External worktree plus two repositories:** Atlas has app/docs repositories and an agent-owned checkout elsewhere. Git establishes the checkout relationship; the person's mapping establishes Atlas. A workspace containing another project does not absorb it into Atlas.
2. **Narrow correction:** a mapping for `projects/atlas` must not capture `projects/atlas-old`. Preview affected deliveries and re-evaluate a stale correction if its source set changed before application.
3. **Imported evidence changes identity:** a provider log moves or an extraction anchor changes. Retain unresolved personal organization for reconciliation; equal filenames or hashes do not authorize transplanting it.
4. **Same bytes, two meanings:** Atlas and Beacon each receive the same boilerplate. Byte storage may deduplicate while project, request and delivery identities remain separate.

The same restraint applies to view state. Current native selection clears `chosenDelivery` when the artifact changes, so restoring a person's per-output choice would be an intentional behavior change. Asynchronous preview/staging results should remain associated with the selection that requested them; source inspection alone does not establish that a stale-result race occurred. See the [current native model](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryModel.swift#L26-L143).

Start with a smaller rendered surface and the real retrieval task. Adopt supporting structure only when the task reveals a continuity problem that existing records and a reversible local choice cannot adequately express.
