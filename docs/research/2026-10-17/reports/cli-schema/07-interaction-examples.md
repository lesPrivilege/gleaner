# Proposed Gleaner interactions

These are design sketches, distinct from the primary-source examples in the atlas.

## Discovering the entry point

A CLI must be available in the agent's environment and introduced through a short usage hint or normal tool discovery. An MCP server must be configured in the host; its tool descriptions explain the jobs it supports. Neither becomes globally discoverable merely by existing. Keep that bootstrap small, then discover project/artifact metadata through queries. Do not make each artifact or section a separate tool definition. Provider tool-search mechanisms can defer loading large tool catalogs, but do not replace artifact search. [Claude's first-party tool-search documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool).

The receiving agent needs the same library/resolver access or an explicitly transferred file. Discovery of a capability does not grant access to the catalog behind it.

Illustrative commands, not implemented or prescribed spellings:

```sh
gleaner find --project-id p7 --query 'retry policy' --limit 10 --json
gleaner inspect --delivery-id d42 --json
gleaner read --delivery-id d42 --sha256 HASH --section s2 --max-bytes 8192 --json
gleaner resolve --delivery-id d42 --sha256 HASH --json
```

Illustrative search response, with abbreviated identifiers:

```json
{
  "schema_version": 1,
  "index_generation": "g18",
  "items": [{
    "artifact_id": "a9", "project_id": "p7", "filename": "report.md",
    "matched_delivery_id": "d42", "matched_fields": ["request"],
    "delivered_at": "2026-09-01T10:00:00Z",
    "provenance": "first_seen_after_delivery", "sha256": "HASH",
    "availability": "saved_copy", "evidence_ref": "e42"
  }],
  "next_cursor": null
}
```

That provenance permits reading the observed copy with its qualifier; it does **not** prove these were the bytes at delivery. An exact-historical requirement should return an explicit inability to prove it. A section result should carry the selected digest, actual range, encoding, completeness and continuation. A handoff reference should carry the same selection plus scope/availability; a temporary path alone is insufficient.

## A bounded content result

Illustrative selection and result, not a current Gleaner API:

```json
{"delivery_id":"d42","sha256":"HASH","section_id":"s2","max_bytes":8192}
```

```json
{
  "delivery_id":"d42", "sha256":"HASH", "provenance":"first_seen_after_delivery",
  "section_id":"s2", "heading":"Retry policy", "encoding":"utf-8",
  "range":{"start_byte":2018,"end_byte_exclusive":2052},
  "content":"Retry policy: wait before trying.\n",
  "truncated":false, "next_cursor":null
}
```

The example content is 34 UTF-8 bytes; the hypothetical range is half-open. A section identifier is valid only for the selected digest; repeated heading text cannot be its sole identifier. Whole-file export remains available for binary or unsupported structured formats.

## The same operations through MCP

An exploratory adapter could expose `find_deliveries`, `inspect_delivery`, `read_delivery` and `resolve_delivery`. A tool response can provide structured metadata plus a resource link. Optional templates such as `gleaner://libraries/{library}/deliveries/{delivery}/captures/{sha}` name exact content; the scheme and ID lifetime still need decisions.

Tools should define application result limits, source scope and schema versions. Do not confuse `tools/list` pagination with pagination of a tool's search results. Include a small textual compatibility rendering if a host cannot consume structured results, and measure its duplication cost.

## Failure and freshness examples

| Situation | Result behavior |
|---|---|
| Two permitted projects called Atlas | Bounded candidates and `ambiguous_project`; no automatic selection |
| Matching delivery has no trusted historical bytes | `historical_bytes_unproven`; offer observed copy only with qualifier |
| Requested hash is missing or fails verification | `version_unavailable` or `content_changed`; no silent fallback |
| Index changed during paging | `stale_cursor` with restart guidance, or a consistent retained generation |
| Indexer encountered unreadable logs | Coverage/scan warning even if items were found |
| Resource outside granted scope | Access failure without enumerating hidden neighbors |
| Original log is gone | Stored evidence remains; exact source expansion is unavailable |

No-match is a successful, scoped search result; malformed requests and access failures are errors. Define CLI exit codes and MCP tool-error mappings explicitly rather than exposing database exceptions. Standard output must contain only the chosen machine format; progress belongs on standard error.

## Handoff reference versus delivery of bytes

A local handoff can return a verified staged filename together with delivery ID, digest, size and qualifier. Staging writes Gleaner's cache even though the source is unchanged; document that side effect. The receiver should verify the digest and tolerate a cleaned cache by resolving again. A local URI is useful only to a consumer with an installed resolver and access to that library.

For another machine, reference passing alone is insufficient. A future authorized transfer must define byte transport, access scope and reference lifetime. Copying a raw session or granting a generic filesystem tool is not necessary to deliver the selected artifact.

If logical-object identity is trialed, a result can additionally carry an `object_ref` and an evidence-backed relation to a revision/representation. An unqualified object reference selects no exact bytes: the consumer must still resolve a particular representation and digest. Keep the source delivery reference even when several deliveries refer to one logical revision.

