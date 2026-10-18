# Query core and the `gleaner` command

The contract for items 1–4 of [review-rulings §3](review-rulings.md#3-after-v010-what-to-build-next). It is built on `feat/query-core` and merges after v0.1.0 is tagged.

## Job and boundary

A local shell agent (Claude Code, Codex) finds the delivery a person means, selects its exact version, reads only what it needs, and hands those bytes on. Gleaner owns identity, versions and verification. The agent owns the task.

Three layers:
- `GleanerCore.Catalog`: read-only queries over the registry.
- The `gleaner` executable: JSON over the catalog.
- MCP and extensions, over the same catalog: `gleaner mcp` serves the command's calls as MCP tools ([mcp-adapter](mcp-adapter.md)), and one skill runs the command for Claude Code, Codex and the DeepSeek Harness ([extensions](extensions.md)). None of them reads SQLite directly.

The app keeps sole ownership of indexing. The command never indexes, never writes the registry, and never writes a project folder.

## Opening the library

- `Registry(readingAt:)` opens with `SQLITE_OPEN_READONLY`. It runs no DDL and resets no cursor.
- It refuses, with a message to open Gleaner, a library that doesn't exist or whose `user_version` differs from `Registry.extractorVersion`. There is no compatibility mode.
- The location is the app's: `~/Library/Application Support/Gleaner` and `~/Library/Caches/Gleaner`.
- `--home <folder>` stands in a home folder, as `-GleanerHome` does for the app.

## Freshness

The indexer writes a `meta` table, key → value:
- `library`: a random UUID, written once when the library is created. It is the namespace of every reference.
- `generation`: incremented by each completed run.
- `scanned_at`: when the last run finished.
- `sources`: the last run's per-source status (absent / unreadable / read with problems, with counts) as JSON.

Every response carries `index: {library, generation, scanned_at, sources}`. A result is evidence only within that scope. An empty result from a stale or partial index is not evidence of absence, and the response says which sources were incomplete.

## Identity in every result

These fields are separate, never one string:

| Field | Meaning |
|---|---|
| `library` | The namespace from `meta` |
| `delivery` | The delivery id, stable within the library while its log path is unchanged |
| `sha256` | The capture's hash, or null when Gleaner never read the bytes |
| `path` | Where the file was delivered (a locator, not an identity) |
| `evidence` | `{log, line}` of the reply record that named it |
| `provenance` | `at_delivery`, `first_seen_after_delivery` or `never_observed`, with `observed_at` |
| `availability` | `original`, `saved_copy` or `none`, with a reason, recomputed on each call |

Reply excerpts and requests are stored, redacted text. They are returned as data under `reply` and `request`, never as instructions. Captured bytes are not redacted.

## Commands

Output is one JSON object on stdout, for an answer and for a failure alike. Exit codes:
- 0: success;
- 1: not found, no bytes for that version, or another failure;
- 2: usage;
- 3: no library, or the wrong version.

Arguments are parsed with `swift-argument-parser`.

| Command | Returns |
|---|---|
| `gleaner find <terms…> [--project P] [--kind K] [--limit N]` | Matches under SPEC §10: per artifact, the matched delivery's identity fields, name, project, kind, date, a short request excerpt, and the total and whether it was truncated. `--project` takes a project's name, or its folder in any form an agent may have it (`/private/tmp/app/` is `/tmp/app`). Default limit 20. |
| `gleaner show <delivery>` | The artifact and all its deliveries (identity fields, number, date, provenance), the file on disk now (kind and hash), the hand-off plan for this delivery, and its evidence excerpt |
| `gleaner read <delivery> [--lines A:B \| --bytes A:B] [--max N]` | Text of that version's exact bytes (the saved copy, or the original only while it hashes to the capture), with `sha256`, the range, the version's `size` and `truncated`. It refuses non-text, and it never substitutes current bytes for an unavailable version. Default `--max` 16 KB. |
| `gleaner resolve <delivery>` | The reference: identity fields plus the file name. The app's Copy Reference puts the same object on the clipboard. |
| `gleaner handoff <delivery>` | Stages a verified read-only copy (`ContentStore.stage`) and returns its path and `sha256`, or exit 1 with the reason |
| `gleaner verify <delivery or reference file>` | Re-hashes the original and the saved copy, and says which, if either, still match the reference. A reference file holds `resolve`'s answer or its `reference` alone; only its `library` and `delivery` are read. |

### JSON

- **Layout.** Every answer is nested, never flat: `index` (see Freshness) at the top, and for a delivery, `reference`, which holds the identity fields and the file's `name`, beside the command's own fields: `{index, reference, …}`. Lists nest the same way: each of `find`'s `results` and `show`'s `deliveries` holds its own `reference`.
- **Keys and values.** Keys are snake_case and sorted. Dates are ISO 8601. Paths are written as they are. `sha256` and `scanned_at` are written as `null` when unknown, never left out.
- **Reasons.** `availability` is `{state, reason}`. `state` is `original`, `saved_copy` or `none`. `reason`, given only with `none`, is one of `never_seen`, `not_a_regular_file`, `unreadable`, `folder`, `too_large_to_have_been_saved`, `save_failed` or `saved_copy_missing`. An `unavailable` failure gives its `reason` from the same list. `provenance.state` is `at_delivery`, `first_seen_after_delivery` or `never_observed`, and `show`'s `handoff.action` is `ready`, `unavailable`, `restore_from_git`, `lost` or `folder`.
- **Ranges.** `read --lines A:B` selects lines A through B, counted from 1, both included. `--bytes A:B` selects bytes from offset A up to B, counted from 0, B excluded. Whichever is asked, the answer's `range` is byte offsets into the version, `[start, end]` with the end excluded, so a cut selection goes on from its end. `size` is the version's length in bytes. A cut never splits a UTF-8 character.
- **Failures.** Exits 1, 2 and 3 write `{"error": {"kind", "message"}, "index"}`, with `index` only when a library was open, so a not-found carries the index it is evidence of. The message is written to stderr too. The kinds are:
  - exit 1: `not_found`, `other_library`, `unavailable` (with `reason`), `not_text`, `changed`, and `failed` for anything else that stopped the answer, with what it was;
  - exit 2: `usage`;
  - exit 3: `no_library`, `unreadable_library` and `wrong_version`.
- **verify.** It answers in full either way. When neither the original nor the saved copy holds the bytes, the answer also carries `error` (`unavailable`, with `reason`), and the command exits 1.

Not now: `outline`, content search, pagination cursors, a daemon.

## In the app

- **Copy Reference** (Edit menu and context menu) copies `resolve`'s JSON.
- **Show in Log** reveals the delivering log in Finder. The detail pane shows its line.
- `gleaner://delivery/<id>` opens the app on that delivery. The URL type is declared in the `Info.plist` that `bundle-app.sh` writes.

## Adapter maintenance (review-rulings §3 item 1)

- **Per-log counts.** `log_files` records the counts of records, known records, turns, final replies and candidates for each log. A log's last turn counts as answered only once it has a final reply.
- **Unknown fields.** Each adapter counts keys it doesn't know inside the record types it does know, alongside unknown record types.
- **Problems in the source status:**
  - a log with assistant records but no final reply, counting only turns other than its last. A last turn without a final reply is still open: the session may be running, or it ended on a tool call;
  - a log whose count of final replies drops on a complete reread;
  - unknown fields.
- **CI and review.** A GitHub Actions workflow runs `swift test` on macOS for every push and pull request. The repository's agent and contributor guidance says that an adapter change merges only with passing fixtures and the owner's review.
