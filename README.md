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

Reads `~/.claude/projects` and `~/.codex` and keeps its own data in
`~/Library/Application Support/Gleaner` (registry, saved copies) and `~/Library/Caches/Gleaner`
(hand-off copies). It never writes to project folders. Search, pick a delivery, and drag the tile:
the receiver gets a copy whose hash was checked after copying.

## Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

Reads `~/.claude/projects` and `~/.codex` (read-only; it runs `git status`, `git cat-file`, and `git log` in the repositories it finds) and writes `out/candidates.tsv`, `out/recall-sample.md`, `out/summary.txt`. `out/` holds log excerpts and is git-ignored.

Options: `--claude-root DIR`, `--codex-home DIR`, `--out DIR`, `--sample N`, `--seed N`.
