# Check record and evidence

Checked 2026-10-17. This appendix records process and limitations; it is not the reader's entry point.

## Scope and environment

- Research began with first-party standards/developer tools, then used public Gleaner main for grounding.
- Separate checkout: `/workspace/gleaner-main`; deliverables: `/workspace/gleaner-research`.
- Praxis was not modified. No private log or credential content was opened. No product source was edited; no commit, push, merge, release, CI change or installation occurred.
- No applicable `/AGENTS.md` or `/workspace/AGENTS.md` was present. `git ls-files '*AGENTS.md' '.agents/*' '.claude/*' '*SKILL.md'` returned no tracked matches in Gleaner. A file listing also found no repository skill instructions. No skill was invoked.
- Linux has Python, Git, ripgrep and `pdftotext`; `command -v swift` found no Swift executable. Native macOS behavior was not exercised.

## Repository pin and independent PR

Executed:

```sh
git clone --single-branch --branch main https://github.com/lesPrivilege/gleaner.git /workspace/gleaner-main
git -C /workspace/gleaner-main switch --detach origin/main
git -C /workspace/gleaner-main rev-parse HEAD
git -C /workspace/gleaner-main ls-remote origin refs/heads/main refs/pull/4/head
```

Results:

```text
HEAD / origin/main: 22dd07d926a764f0a2efcdeb093b78f0b9eab41b
remote main:       22dd07d926a764f0a2efcdeb093b78f0b9eab41b
PR #4 head:        72a42993512281a8bcc36fd9c6f22566132258d9
```

The [PR page](https://github.com/lesPrivilege/gleaner/pull/4) showed open/unmerged. Its reported tests are the author's evidence, not tests run here. No PR source was checked out or merged. Main's design `structure.md` discusses the next round, but that is not evidence those views exist on main.

## Grounding claims

All links below pin main's full SHA.

| Claim | Source location |
|---|---|
| Native macOS 15; core library; CLI spike; no declared external packages | [Package.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Package.swift) |
| Product boundary, path identity, timestamps, capture confidence, storage, privacy and future connections | [SPEC §§1–6, 10–14](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/SPEC.md) |
| Project context, original filenames and progressive disclosure adopted; dossiers/aliases declined | [Design rulings](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/design/rulings.md) |
| Thread/outline/timeline are a later round; no inferred lineage | [Structure](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/design/structure.md) |
| CLI is diagnostic extraction/labeling, with standard local-log defaults | [Spike main](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/gleaner-spike/main.swift) |
| Capture/provenance and delivery fields; artifact ID is path | [Library.swift:5, 44, 83](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Library.swift#L5) |
| Handoff distinguishes original/saved copy and late observation | [Library.swift:227](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Library.swift#L227) |
| Search is lowercased substring matching within one delivery plus filename/project | [Library.swift:249](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Library.swift#L249) |
| Delivery ID hashes log path, first evidence line and artifact path | [Indexer.swift:28](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Indexer.swift#L28) |
| Delivery numbers derived on load; registry constructor may migrate/invalidate cursors | [Registry.swift:13, 99](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Registry.swift#L13) |
| Database opens read/write/create; WAL and timeout pragmas | [Database.swift:16](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Database.swift#L16) |
| Staging hashes copied bytes, preserves supplied filename, changes only own copies | [ContentStore.swift:73](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/ContentStore.swift#L73) |
| Project label from git file/commondir traversal, cwd fallback, cached roots | [Projects.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Projects.swift) |
| Comparison verifies selected endpoints; text limits apply | [Comparison.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Comparison.swift) |
| Main parses Markdown blocks without a source-range API | [MarkdownBlocks.swift:15](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/MarkdownBlocks.swift#L15) |

These are integration constraints, not new pre-release defect findings. No performance or usability conclusion is inferred from source inspection alone.

## External checks

The source atlases link each original source and relevant release/license. Important version observations:

- MCP `specification/latest` redirects to `2026-07-28`. The 2025-11-25 pages remain available; examples explicitly select that dialect.
- MCP Swift SDK release page marks `0.12.1` latest. Release commit `a0ae212ebf6eab5f754c3129608bc5557637e605` was resolved through its commit link. Pinned README declares 2025-11-25. Manifest and license were read. This supports a compatibility question, not a claim that every newer feature fails.
- GitHub CLI release page marks `v2.102.0` latest; tagged MIT license checked.
- Swift Argument Parser release page marks `1.8.2` latest; tagged Apache license and runtime library exception checked. A later-listed maintenance release does not override the explicit latest marker.
- GitHub MCP Server release page marks `v2.0.2` latest; main README documents projections/read-only configuration and MIT license. Its guessed `pkg/github/repos.go` tag path returned 404; behavior claims are README-level.
- ripgrep printer and dual license checked at `15.1.0`; release page inspected. Installed binary behavior was tested separately, not assumed to match that exact version.
- DataHub code inspected at `v1.6.0.3`; release page also shows `v1.8.0rc5`. No claim that the prerelease is stable. Apache-2.0 in repository license section.
- Sourcegraph's Zoekt repository identifies itself as the maintained fork and Apache-2.0. No benchmark or maintenance guarantee was inferred.
- SQLite FTS5 documentation, copyright and release chronology read. Availability in Gleaner's supported macOS builds was not tested.
- DCAT 3 and PROV-DM were read from W3C recommendations; OCI descriptor from `v1.1.1`. A2A and Zenodo examples are documentation-derived, not live integrations.
- Buneman/Khanna/Tan and PRISM author-hosted PDFs were read. Rahm/Bernstein's publisher abstract was read; the full article is subscription content, so the summary is limited to its taxonomy and scope.

## Access limitations and resolution

`python3 evidence/fetch_public.py` attempted unauthenticated metadata reads at `https://api.github.com/repos/{repository}` for ten public repositories. Every request failed with `Tunnel connection failed: 403 Forbidden`. Outcome: **denied by the network proxy; no response data obtained**. Recorded in [public-sources.json](public-sources.json). No credentials, proxy bypass or elevated retry was used. Browser-visible documentation/source and the authorized Git clone supplied the necessary evidence; automated API maintenance snapshots remain unavailable.

Some guessed URLs failed or redirected: the old Penn provenance PDF, Microsoft publication URL, Zenodo help paths and a GitHub source path. The VLDB PRISM PDF timed out; the ACM article page returned 403. The author-hosted UCLA paper was independently discoverable and readable. These failed locations are not used as substantive evidence. No denied action is pending or has an uncertain side effect.

## Executed validation

```sh
python3 /workspace/gleaner-research/probe/probe.py
git -C /workspace/gleaner-main status --porcelain=v1
git -C /workspace/gleaner-main diff --exit-code
```

Probe: four policies × ten cases × fifteen repetitions; all expected-outcome assertions passed, plus corrupt-copy refusal and an explicitly reproduced stale-catalog false negative. [Raw results](../probe/results.json). Script-only tests do not validate model behavior or Gleaner's implementation. `git status` was empty and diff exited zero.

Git `cat-file` and ripgrep synthetic runs also exited zero; [exact commands/output](command-examples.json). Native `swift test`, UI tests and MCP client conformance were not run. No existing release gates were closed.

Parent-review clarification: evaluation now states each policy's prior knowledge, engineered fixture correctness and excluded preparation costs. Probe code/results were unchanged, so no new timing run was made. [Source-access record](source-access.md) distinguishes full-paper originals, the accessible Rahm/Bernstein abstract and failed locations. Package remains local; public delivery is pending parent coordination.
