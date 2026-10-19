# Progressive query experiment

Status: bounded implementation experiment, not a ratified API or release decision. The owner's
later steering requires source-grounded intent/spec/implementation convergence before finalizing
the build. Existing design documents remain the decision record.

## Question and contract conflict

Can an agent discover the app's project scope, select one delivered report, locate a heading such
as R1, and obtain exact version bytes without reading the entire report into its context?

`docs/design/query-core.md` explicitly deferred outline, content search and pagination cursors.
The new goal requests progressive logical objects, including document sections. This experiment
adds report-scoped heading access and offset pagination to test that narrower case. It does not
ratify a broader logical-object model, message-backed findings, automatic links between findings,
semantic acceptance/currentness, global content search or a new storage schema.

## Implementation boundary

- `Catalog.projects` projects the same `Organization` the app uses, including corrections and
  user projects. Stable keys identify project context; names, folders and checkout paths remain
  separate. `find --project` also accepts that key.
- `Catalog.find` keeps `Organization.search` and its order. Optional `offset` and `generation`
  support continuation; the legacy response shape stays unchanged. Pages have 1–1000 entries.
  The former API allowed arbitrary positive limits; this bound is a deliberate compatibility
  change for review, not an accidental change to relevance ranking.
- `Catalog.outline` uses `Catalog.read` to verify exact captured text. It recognizes source
  Markdown ATX and single-line setext headings outside fenced and indented code, with byte
  ranges including nested sections. Terms match titles in the selected document only.
- `Catalog.readSection` accepts the exact derived section ID, bound to library, delivery, hash
  and byte span. A title like R1 is neither a global identity nor a claim about a finding's status.
  Returned text is data and is never executed. Original/saved-copy availability and delivery
  evidence remain in the parent reference.
- `gleaner projects`, `outline`, `section` and their MCP tools only call these core methods.
  There is no second search algorithm and no write to the registry or project files.

## Reproduce the interaction

After building and indexing an authorized synthetic home:

```sh
gleaner projects --home "$fixture_home" --limit 20
gleaner find review --project "$project_key" --home "$fixture_home"
gleaner outline "$delivery_id" R1 --home "$fixture_home"
gleaner section "$delivery_id" "$section_id" --max 16384 --home "$fixture_home"
```

`projects` and `outline` return `next_offset` when another page exists. For `find`, continue with
the previous offset plus `results.count`, retaining the same terms, filters and index generation.
`projects`/`find --generation` refuse a different completed run. This is not a frozen snapshot:
corrections, source settings and an ongoing indexing run can change state within a generation.
Stable pagination under concurrent writes remains a design question.

Outline refuses text over 4 MiB rather than returning a misleading partial outline. Section
output is bounded at 1 MiB, default 16 KiB, and truncates only between UTF-8 characters. Continue
via the existing `read --bytes` using the returned range end and the section range end. Direct
`read` remains available for larger documents. A format without recognized headings returns an
empty `markdown_headings` outline; that is not evidence that the document has no useful findings.
This is a source-outline subset, not a full CommonMark renderer (nested list/HTML blocks and
multiline setext titles are not interpreted).

## Verification and remaining decisions

Focused tests cover core/app project identity parity, shared search page order, generation
mismatch, repeated finding IDs in different reports, exact CRLF/non-ASCII ranges, nested sections,
fences, saved-version recovery, unavailable versions, bounds, no mutation and CLI/MCP JSON parity.
Execution results belong in the run reports; this document does not turn source inspection into a
passing test claim.

Decisions still needed: whether these APIs belong in the product now; how section objects relate
to message findings and review state; whether heading-only discovery sufficiently reduces task
effort; whether offset continuation needs a stronger snapshot token; and whether the fixed parse
bound suits real report workloads. Finder/library superiority is unmeasured.

The MCP prototype retains the installed official SDK's negotiated protocol versions. Its tool
shape was checked against the official [tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
and [stdio transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports):
JSON Schema inputs, structured content plus text, tool errors in `isError`, and protocol-only
stdout. Adding tools does not claim support for a newer protocol version.
