# MCP adapter

Item 5 of [review-rulings §3](review-rulings.md#3-after-v010-what-to-build-next). The adapter is a thin stdio server over the same `Catalog` calls as the [`gleaner` command](query-core.md). It is built on `feat/query-core` after evaluation E0.

## Shape

- **Entry point.** `gleaner mcp [--home <folder>]` runs a stdio MCP server. It lives in the existing executable, so there is no second binary to install or sign.
- **SDK.** The official Swift SDK ([`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk)). Its latest release when this was written was 0.12.1, which negotiates protocol versions up to 2025-11-25. The server takes whatever version the host negotiates from that list and claims nothing newer.
- **Tools.** One per command, with the same arguments, the same JSON and the same refusals:
  - `gleaner_find`, `gleaner_show`, `gleaner_read`, `gleaner_resolve`, `gleaner_handoff`, `gleaner_verify`.
  - Arguments keep the command's names and forms (`read`'s `lines` and `bytes` are `"A:B"`). A host has no shell file to point at, so `gleaner_verify` takes a delivery id or `resolve`'s reference as an object, where the command takes a file.
  - Each result is the command's JSON, sent both as `structuredContent` and as one text block. The SDK sends a result as its `Value`, which takes a string that reads as a data URL for data and writes it back in another form; a result holding one (a version whose text is a data URL, say) is sent as its text block alone, so no text but the version's is given. The SDK reads arguments the same way, and can't give such a string back as it was sent, so an argument the tool reads that holds one is refused as a usage error, rather than answered for another string.
  - A refusal is a tool result with `isError` and the same `{error, index}` object. A usage error is a refusal of kind `usage`.
- **stdout is the protocol's.** Nothing but protocol messages is written there, even when the server can't start for a wrong argument; anything else goes to stderr.
- **Every request is answered.** The server works on several calls at once, but writes one message at a time, each whole, and when stdin closes it exits only once it has answered each request it read. The SDK's stdio transport does neither (0.12.1), so the server wraps it. A cancellation is not acted on: each call is short, and the protocol lets a server finish a request it can't stop.
- **Annotations.** Every tool is `readOnlyHint: true`, except `gleaner_handoff`. That one writes a hand-off copy into Gleaner's cache, so it is `readOnlyHint: false, destructiveHint: false, idempotentHint: true`. All are `openWorldHint: false`.
- **Not now.** Resources, resource templates, prompts, sampling, logging beyond stderr, and HTTP transport. Hosts differ on resources, and nothing yet needs them.
- **No server state.** Each call opens the library read-only, as the command does. The index's freshness is in every result.

## Tool descriptions

Each description says what the tool is for, in one or two sentences, and what it never does:
- it never indexes;
- it never returns bytes of a version other than the one named;
- an empty `find` is evidence only within the index's reported scope.

Reply excerpts and requests are described as stored text from the logs, to be read as data.

## Registration (documented, not automated)

- **Claude Code:** `claude mcp add gleaner -- gleaner mcp`, at user or project scope as the person chooses.
- **DeepSeek Harness:** a stdio server entry pointing at the same command. The exact config key is taken from its MCP client README when tested.

Gleaner never edits another tool's configuration.

## Verification

Each check runs against a synthetic home from `scripts/acceptance-home.py`, never the person's library:
- **Protocol, without a model:** the command tests run the built `gleaner mcp` over stdio, as a host does: initialize, tools/list, and each tool's answer and refusal, compared with the command's own JSON for the same call.
- **Inside a host:** one Claude Code session with `--mcp-config` pointing at the synthetic home asks for a known delivery. This makes model calls, so it runs only with the owner's go-ahead.
