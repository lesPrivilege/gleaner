# Source atlas: interfaces and progressive retrieval

These precedents supply mechanisms, not evidence that one interface improves Gleaner users' outcomes. Maintenance and license checks are in the [check record](evidence/check-record.md). No dependency was installed.

## GitHub CLI: fields before formatting

**Works:** commands expose selected JSON fields; `--jq` transforms structured results. The manual also explains field discovery. [Original manual](https://cli.github.com/manual/gh_help_formatting).

Documented command, inspected rather than run against an account:

```sh
gh pr list --json number,title,author
```

It returns objects with those fields. **Transfer:** explicit structured output, bounded defaults, stable names and discoverable help. Keep diagnostics on standard error and payloads on standard output. Define exit status separately from empty results. Field projection reduces output, but is not authorization.

**Context:** GitHub-maintained; [releases](https://github.com/cli/cli/releases) expose `v2.102.0`; [MIT license](https://github.com/cli/cli/blob/v2.102.0/LICENSE). A design precedent, not a Gleaner dependency.

## ripgrep: structured matches without a prebuilt index

**Works:** JSON Lines messages carry event type, path, line, offsets and match details. Non-UTF-8 bytes are represented explicitly. [Tagged printer implementation](https://github.com/BurntSushi/ripgrep/blob/15.1.0/crates/printer/src/json.rs).

Run on a synthetic file:

```sh
rg --json -n -F 'Retry policy' report.md
```

Observed match (temporary directory omitted):

```json
{"type":"match","data":{"path":{"text":"report.md"},"lines":{"text":"Retry policy: wait 30 seconds.\n"},"line_number":2,"absolute_offset":9,"submatches":[{"match":{"text":"Retry policy"},"start":0,"end":12}]}}
```

**Transfer:** competent shell retrieval already filters before loading model context. Gleaner should improve selection and reconstruction, not assume all direct reading is brute force. **Context:** inspected tag `15.1.0`; [MIT or Unlicense](https://github.com/BurntSushi/ripgrep/blob/15.1.0/COPYING). [Exact run evidence](evidence/command-examples.json).

## Git plumbing: resolve immutable state, then read

**Works:** `cat-file` returns type/size without content, then supplies selected bytes. Batch output includes explicit missing objects. [Original manual](https://git-scm.com/docs/git-cat-file).

Run against pinned Gleaner main:

```text
git cat-file --batch-check=%(objectname) %(objecttype) %(objectsize)
input: HEAD:docs/SPEC.md
output: 5f15eaa73eb376886df00713bdd40f65ce8206f9 blob 23795
input: HEAD:does-not-exist
output: HEAD:does-not-exist missing
```

**Transfer:** resolve a moving name once, carry an exact identifier and expose unavailability. A commit does not establish what was delivered; uncommitted outputs need captures.

Worktrees share repository data while retaining per-worktree state; `worktree list --porcelain` provides machine output. **Transfer:** repository affiliation and working location are distinct. [Worktree manual](https://git-scm.com/docs/git-worktree). No Git storage redesign is proposed.

## MCP: discovery and content are separate primitives

**Works:** tools describe operations and schemas; resources identify readable context by Uniform Resource Identifier (URI); templates parameterize addresses. The host decides how resources enter context. [Tools, 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [resources, same revision](https://modelcontextprotocol.io/specification/2025-11-25/server/resources).

Adapted minimal interaction using that protocol revision, after initialization:

```json
{"jsonrpc":"2.0","id":1,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":1,"result":{"resources":[{"uri":"file:///project/report.md","name":"report.md","mimeType":"text/markdown"}]}}
{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"file:///project/report.md"}}
{"jsonrpc":"2.0","id":2,"result":{"contents":[{"uri":"file:///project/report.md","mimeType":"text/markdown","text":"# Report\n"}]}}
```

**Transfer:** discover lightweight entries, then fetch selected content. Templates can describe delivery/capture addresses without enumerating every section. Search and range reads still need application semantics. A resource link does not guarantee that a receiver will fetch it.

**Version boundary:** `latest` resolves to [2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28). That revision changes request metadata/result requirements; resource/template listing supports caching and pagination. The example deliberately uses 2025-11-25, not a mixed dialect. Pin the negotiated version and test clients.

Standard input/output (stdio) runs a local subprocess; keep protocol output clean. Root lists guide scope but do not replace access enforcement. [Transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [roots](https://modelcontextprotocol.io/specification/2025-11-25/client/roots).

## Swift libraries: useful adapters, optional dependencies

**MCP Swift Software Development Kit (SDK):** official client/server implementation. Inspected release `0.12.1`, commit `a0ae212ebf6eab5f754c3129608bc5557637e605`, declares 2025-11-25 support. Examples register list/call handlers and use `StdioTransport`. [Pinned README](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/README.md).

**Transfer:** evaluate for protocol handling; do not assume current-spec compatibility. The [manifest](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/Package.swift) includes Swift System, Logging, EventSource and other package dependencies. The [license](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/LICENSE) distinguishes new Apache-2.0 contributions from existing MIT code.

**Swift Argument Parser:** typed arguments/options, subcommands and help reduce parsing work. [Official repository](https://github.com/apple/swift-argument-parser), [releases](https://github.com/apple/swift-argument-parser/releases). Latest marker observed on `1.8.2`; [Apache-2.0 with Swift exception](https://github.com/apple/swift-argument-parser/blob/1.8.2/LICENSE.txt). It does not supply result schemas or resolution rules. Adopt only if the consumer CLI warrants it.

## GitHub MCP Server: projections and explicit versions

**Works:** `get_file_contents` accepts repository/path, ref or commit SHA, and directory field projection. `get_commit` offers metadata/stats/full-patch detail. Read-only mode removes write tools; allowlists reduce the exposed surface. [Official documentation](https://github.com/github/github-mcp-server).

Adapted arguments from the documented schema:

```json
{"name":"get_file_contents","arguments":{"owner":"example","repo":"demo","path":"docs","sha":"COMMIT","fields":["name","type"]}}
```

Directory responses are structured entries; files can return content/resource links. **Transfer:** small default detail and exact revisions. Its breadth is not a template for Gleaner's tool count. Read-only still discloses information.

**Context:** GitHub-maintained, MIT; [release `v2.0.2`](https://github.com/github/github-mcp-server/releases/tag/v2.0.2). README behavior was inspected; a guessed tagged code path returned 404, so no function-level implementation claim is made.

## SQLite FTS5: lexical retrieval without another database

**Works:** full-text queries, phrase/prefix matching, BM25 ranking and source snippets. External-content indexes require synchronization. [Original documentation](https://www.sqlite.org/fts5.html).

Illustrative SQL using documented functions:

```sql
SELECT rowid, snippet(delivery_search, -1, '[', ']', '…', 24)
FROM delivery_search WHERE delivery_search MATCH ?
ORDER BY bm25(delivery_search) LIMIT 10;
```

**Transfer:** one delivery's evidence can remain one search unit. Content indexing is separate. Tokenized matching changes today's substring semantics; test it. **Context:** SQLite is public domain and actively released; check macOS feature availability. [Copyright](https://www.sqlite.org/copyright.html), [release history](https://www.sqlite.org/chronology.html).

## Sourcegraph and Zoekt: coverage is part of the answer

**Works:** streaming search reports matches, progress, alerts and completion. Matches identify repository, commit, path and lines. `count:` stops after a threshold; display limits only bound returned matches. Skipped coverage is reported. [Original API](https://sourcegraph.com/docs/api/stream-api).

Documented request pattern, with schematic response:

```text
GET /.api/search/stream?q=r:sourcegraph/sourcegraph%20stream%20results%20patternType:keyword%20count:1&v=V3
event: matches
data: [{"type":"content", "path":"…", "commit":"…", "lineMatches":[…]}]
event: done
data: {}
```

**Transfer:** expose limits, freshness and revision; no match may not mean exhaustive absence. No live Sourcegraph query was run.

[Zoekt](https://github.com/sourcegraph/zoekt) is Sourcegraph's maintained trigram code-search engine, supporting substring/regular-expression queries and code-oriented ranking; Apache-2.0. It is a mature mechanism, but excessive for a small delivery catalog without measured scale/recall needs.
