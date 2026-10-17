# Gleaner

Finds what your agents delivered, wherever they left it. See [docs/SPEC.md](docs/SPEC.md).

## Layout

- `Sources/GleanerCore` — provider adapters (Claude Code, Codex), mention extraction, locator, redaction,
  the registry (SQLite), the content store (saved copies, verified hand-off copies), the indexer, the
  log watcher, and the status logic (`Library.swift`).
- `Sources/Gleaner` — the macOS library app (SwiftUI + AppKit, Quick Look).
- `Sources/gleaner-spike` — Spike A: read-only extraction over local logs, writes a labeling sheet.
- `Tests/GleanerCoreTests` — fixture tests from sanitized record shapes, and the library flow
  (concurrent edits, deleted worktrees, rollback, backfill, verified staging).

## App

```bash
./scripts/bundle-app.sh && open build/Gleaner.app
```

Search, pick a delivery, and drag the tile (or press ⌘C in the list, ⌘O to open): the receiver gets
a copy whose hash was checked after copying.

### What it reads and keeps

- Reads Claude Code logs in `~/.claude/projects` and Codex logs in `~/.codex`, and the files those
  logs name. It runs read-only git commands (`--no-optional-locks`) in the repositories it finds.
- Keeps excerpts of replies and requests, redacted of secret-shaped strings, never whole logs.
- Keeps its registry and saved copies in `~/Library/Application Support/Gleaner`, and hand-off
  copies in `~/Library/Caches/Gleaner`, which is safe to clear.
- Never writes to project folders. Gleaner itself makes no network requests; a Quick Look preview of
  a web page may load what that page references, and links open only when you click them.

### Release build

```bash
./scripts/release.sh
```

Runs the tests and writes `build/Gleaner-<version>.zip` with its sha256. A tagged commit
(`v0.1.0`) builds as that version; anything else builds as `0.1.0-dev+<commit>`.

The zip is ad-hoc signed, not notarized. On another Mac, unzip it, move Gleaner to Applications,
and open it with Control-click → Open the first time. Notarization needs a Developer ID.

## Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

Reads `~/.claude/projects` and `~/.codex` (read-only; it runs `git status`, `git cat-file`, and `git log` in the repositories it finds) and writes `out/candidates.tsv`, `out/recall-sample.md`, `out/summary.txt`. `out/` holds log excerpts and is git-ignored.

Options: `--claude-root DIR`, `--codex-home DIR`, `--out DIR`, `--sample N`, `--seed N`.
