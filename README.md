# Gleaner

Finds what your agents delivered, wherever they left it. See [docs/SPEC.md](docs/SPEC.md).

## Layout

- `Sources/GleanerCore` — provider adapters (Claude Code, Codex), mention extraction, locator, redaction.
- `Sources/gleaner-spike` — Spike A: read-only extraction over local logs, writes a labeling sheet.
- `Tests/GleanerCoreTests` — fixture tests built from sanitized real record shapes.

## Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

Reads `~/.claude/projects` and `~/.codex` (read-only; it runs `git status`, `git cat-file`, and `git log` in the repositories it finds) and writes `out/candidates.tsv`, `out/recall-sample.md`, `out/summary.txt`. `out/` holds log excerpts and is git-ignored.

Options: `--claude-root DIR`, `--codex-home DIR`, `--out DIR`, `--sample N`, `--seed N`.
