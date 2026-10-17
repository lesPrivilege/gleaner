# Let agents find a delivery before reading its history

Gleaner could give agents a useful progressive entry point: find the intended output in the right project, select an evidenced version, inspect only relevant content, then hand over verified bytes. A command-line interface (CLI) or Model Context Protocol (MCP) server can expose this behavior; reliable identity and version selection must come from Gleaner.

Start with a small query/read application programming interface (API) over GleanerCore. A CLI can return JavaScript Object Notation (JSON); add MCP when clients need it. Logical objects may improve continuity across paths, but are not prerequisites.

## Start with the user's job

| Job | Small useful result | Escalate only when needed |
|---|---|---|
| Find the intended delivery | Project scope, original filename, matched request/excerpt, matching delivery ID and date | Other candidates and original evidence |
| Choose an old version | Delivery events, capture hash, availability and observation provenance | Resolve one exact capture; do not substitute current bytes |
| Understand what changed | Hash/size comparison, then bounded text diff of selected endpoints | Read surrounding content; inspect code/tests for behavioral claims |
| Inspect one part | Actual headings or a short verbatim passage tied to a hash | Read a section or bounded line/byte range |
| Trace evidence | Provider, delivery event, stored excerpt and source locator | Authorized bounded original-message retrieval, if still available |
| Give another agent the artifact | Exact delivery/capture reference, original filename, verified copy and digest | Explicit transfer when the receiver cannot access the local filesystem |

“Intended” is supported by delivery evidence; an assistant’s “approved” or “tests pass” claim is not verified status.

## What main already supplies

Gleaner’s local macOS core already has delivery records, capture provenance, saved copies, version comparison and verified staging. Artifact identity is currently the path; identical bytes at different paths remain separate. Project affiliation folds worktrees through their repository. Search requires all terms within one delivery's context and opens the matching delivery. [Specification](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/SPEC.md), [core model](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Library.swift).

`gleaner-spike` emits extraction-labeling files. A consumer CLI should expose core retrieval rather than standardize those diagnostic exports. Threads, outline navigation and project timeline are in unmerged [PR #4](https://github.com/lesPrivilege/gleaner/pull/4), separate from main. Main's Markdown parser supplies block structure, but not a stable source-range retrieval API.

## Three viable implementation paths

| Path | What it adds | When it earns its cost | Main tradeoff |
|---|---|---|---|
| A. Structured CLI first | A new consumer executable with find, inspect/read and resolve operations | Local agents already have shell access | Installation/help discovery and per-command startup; CLI output needs its own compatibility discipline |
| B. Thin MCP adapter | A few tools mapped to shared functions; optional exact-version resources | Target clients reliably expose MCP tools and need discoverability | Client/resource support varies; SDK, protocol and process lifecycle add work |
| C. Shared query/read core, two adapters | Typed request/results within GleanerCore; CLI and MCP translate them | More than one consumer is actually needed | Slightly more initial separation, fewer divergent search/version rules later |

C is a code boundary; A can implement it first without a daemon. B could invoke a structured CLI, adding process/error overhead. An MCP sidecar querying raw SQLite would couple it to schema, redaction and migrations.

One practical constraint: today's `Registry` initialization creates/migrates tables and invalidates extraction cursors. A read command needs a deliberately read-only opening path or an app-owned query endpoint; simply instantiating the existing initializer is not a purely observational operation. Keep indexing ownership explicit. [Registry](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Registry.swift), [database opening](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Database.swift).

## A small retrieval vocabulary

Keep three layers distinct:

1. **Navigation metadata:** project identity, filename, matching delivery, type, dates, availability, provenance, permitted next operations. No whole documents.
2. **Factual preview:** actual headings, line counts, bounded verbatim excerpts, or computed differences, each anchored to selected bytes. No generated interpretation required.
3. **Content:** exact text ranges or a verified file copy. A preview limit must never masquerade as complete content.

Git separates object metadata from content; GitHub CLI projects explicit JSON fields; Sourcegraph reports matches, limits and skipped coverage. These support small, inspectable responses without making summaries the source of truth. [Git](https://git-scm.com/docs/git-cat-file), [GitHub CLI](https://cli.github.com/manual/gh_help_formatting), [Sourcegraph](https://sourcegraph.com/docs/api/stream-api).

[Interaction examples](07-interaction-examples.md) preserve one delivery and digest through discovery, reading and handoff.

For MCP, tools are a practical discovery route; resources identify readable material, and templates describe URI patterns. Resource listing does not guarantee that every host lets a model search resources. MCP list pagination does not automatically paginate an artifact's content. Use a bounded read tool or explicit section/range resource semantics. Test host behavior. The inspected Swift SDK declares an older protocol revision than the current specification; compatibility needs a concrete client check. [Resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources), [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

## Reliability decisions that matter

- **Identity:** display names and delivery numbers are not durable machine selectors. Main derives delivery IDs from log path, line and artifact path; renaming a log or changing its layout can change those IDs. Define the promised stability boundary before exposing handles. Retain the original filename and a library namespace; do not silently claim rename continuity.
- **Project/worktree scope:** a repository basename can collide. Return a distinguishable repository/root reference and the delivery's worktree context. Never equate repositories solely because they share a remote or label. Missing worktrees may leave affiliation uncertain.
- **Search:** preserve current per-delivery matching as the first documented mode. State fields searched, case/substring behavior, sorting and truncation. Keep content search distinct. Full-Text Search 5 (FTS5) offers useful indexing in existing SQLite, but its token matching is not a drop-in equivalent to today's substring semantics. [FTS5](https://www.sqlite.org/fts5.html).
- **Bounded reads:** pin the hash before outline/section selection. Duplicate headings need occurrence/range identifiers; headings inside code fences are not sections. Specify UTF-8 bytes versus characters and line numbering. For unsupported binary formats, offer metadata and verified file access.
- **Freshness:** report index generation, last successful scan and partial failures separately from file verification time. Bind cursors to filters, ordering and generation; reject stale cursors or serve a consistent snapshot. An empty stale index is not evidence of absence.
- **Availability:** distinguish missing original, available saved copy, known digest with unavailable bytes, and never-observed delivery. Reverify selected bytes. Never replace a requested unavailable version with a nearby version.
- **Exposure:** default to a local, limited library/project scope. Return minimal redacted delivery evidence, not a transcript browser. Captured artifact bytes are not redacted; source references can expose private paths. Retrieval text remains data and cannot change tool policy or authorize reading more files. Read-only operations still disclose information.

## Adoption and stopping points

First test a small read surface against real retrieval jobs using synthetic or consented fixtures. Measure against competent `rg` plus section reads, not only bulk reading. Add the transport that removes actual friction. Expand content indexing only when missing recall is observed; investigate logical identity when rename/role errors recur. Keep schema and transport evolution separate from capture identity.

The isolated probe achieved the same expected outcomes for all four scripted policies. Ten tasks emitted 4,885 bytes via catalog access versus 5,967 via targeted session filtering plus section reads; full-document and exhaustive baselines emitted much more. Those are synthetic measurements, not agent success rates or token savings. [Methods and results](05-evaluation.md).

Direct code/log reading remains necessary for undisclosed outputs, extraction misses, implementation behavior, tests, rationale beyond stored excerpts, or cross-file dependencies such as HTML bundles. Gleaner can route the next read, not certify a project's complete knowledge. The logical-object alternative and its costs are developed in [the separate comparison](04-logical-object-options.md).
