# MCP adapter

Item 5 of [review-rulings §3](review-rulings.md#3-after-v010-what-to-build-next). The adapter is a thin stdio server over the same `Catalog` calls as the [`gleaner` command](query-core.md). It is built on `feat/query-core` after evaluation E0.

## Shape

- **Entry point.** `gleaner mcp [--home <folder>]` runs a stdio MCP server. It lives in the existing executable, so there is no second binary to install or sign.
- **SDK.** The official Swift SDK ([`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk)). Its latest release when this was written was 0.12.1, which negotiates protocol versions up to 2025-11-25. The server takes whatever version the host negotiates from that list and claims nothing newer.
- **Tools.** One per command, with the same arguments, the same JSON and the same refusals:
  - `gleaner_find`, `gleaner_show`, `gleaner_read`, `gleaner_outline`, `gleaner_resolve`, `gleaner_handoff`, `gleaner_verify`.
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

Reply excerpts, requests and an outline's headings are described as stored text from the logs, to be read as data.

## Registration (documented, not automated)

- **Claude Code:** `claude mcp add gleaner -- gleaner mcp`, at user or project scope as the person chooses.
- **DeepSeek Harness:** a row for its MCP client, `@deepseek-ai/dsh-mcp-client`, inserted in `$DSH_HOME/cordis.patch.yml` or in a file passed with `--patch`: `serverName: gleaner`, `transport: stdio`, `command` the path to `gleaner`, `args: [mcp]`. Its tools are then named `mcp__gleaner__gleaner_find` and so on. This is taken from the client's README ([extensions](extensions.md#sources)) and not yet run in a Harness session.

Gleaner never edits another tool's configuration.

## Verification

Each check runs against a synthetic home, never the person's library:
- **Protocol, without a model:** the command tests run the built `gleaner mcp` over stdio, as a host does, on the synthetic home they build for the command: initialize, tools/list, and each tool's answer and refusal, compared with the command's own JSON for the same call.
- **Inside a host:** one Claude Code session with `--mcp-config` pointing at a synthetic home from `scripts/acceptance-home.py` asks for a known delivery. This makes model calls, so it runs only with the owner's go-ahead.

**Run on 2026-10-18**, the command built at `7ed0e10`, in Claude Code 2.1.302 (`claude -p`, Opus 5.5) with `--mcp-config` naming only `gleaner mcp --home <home>`, `--strict-mcp-config`, and none of the person's own settings, on a home after `initial`, read to generation 1:
- Asked for "the recovery guide's first version" and to hand it off, the session called `gleaner_find` with `terms` `["recovery", "guide"]`, which listed all nine files of that reply, then `gleaner_show` and `gleaner_handoff` on guide.md's delivery.
- It took delivery 1, the only delivery of guide.md, and said so. The hand-off copy is read-only, and its hash is the delivery's `sha256`.
- It gave the copy's path, the delivery's date and request, and that latest.md has the same hash. No call was refused.
- Claude Code deferred the six tools behind its tool search, so the session loaded them before the first call.

**Rerun on 2026-10-18**, built at `86018e6`, on a new home after `initial` and `second`, read to generation 2. Now guide.md has two deliveries: delivery 2 is on disk, and delivery 1 is only in a saved copy. `find recovery guide` matches delivery 1 alone, since delivery 2's request doesn't name the guide.
- The calls were the same: `gleaner_find` (nine files, not truncated), then `gleaner_show` and `gleaner_handoff` on delivery 1. From `deliveries` the session said the file on disk is now version 2, so version 1 comes from Gleaner's saved copy.
- The copy holds version one's text, and its hash is delivery 1's `sha256`. It named delivery #1, its date and request, and the hash on disk now.
