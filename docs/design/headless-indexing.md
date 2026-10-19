# Headless indexing

Option D is built, as ruled 2026-10-19; E0's preparation stays on the app. Goal: an agent measures whether Gleaner admits the right files, and all of them, on a synthetic home (`scripts/acceptance-home.py`, the E0 worlds), through `gleaner` and `gleaner mcp`, without computer use.

## Where it stands

- `gleaner` and `gleaner mcp` read a library and never make one: a missing one is `no_library`, exit 3 ([query-core](query-core.md): "The app keeps sole ownership of indexing").
- E0 already indexes without computer use: `eval/prepare.py` runs `open -n build/Gleaner.app --args -GleanerHome <world>`, polls the library's `generation` read-only, then kills the app.
- What the app's run writes depends only on the `Indexer` that `LibraryModel.init()` sets up (`LibraryFolders(home:)`, `indexer.home = home`) and on `indexer.run(providers: all − sourcesOff)`. Nothing else at launch writes the library. A run without the window would make the same library.

What blocks an agent today with the E0 path: it needs `Gleaner.app` bundled in release (`scripts/bundle-app.sh`), a logged-in GUI session, a window that takes focus, and a poll-and-kill loop. It can't run in CI, over SSH, or from a sandboxed agent shell, and it is slow (a release build plus app launch for each world).

## Options

| | What | For | Against |
|---|---|---|---|
| A | Keep E0's way; wrap it as `scripts/index-home.sh <home>` | No code change; indexes exactly as shipped | Still GUI, bundle, focus, polling; not CI or SSH |
| B | `GleanerApp --index-once -GleanerHome <home>`: the app binary runs one index and exits before any window | One binary sets up the indexer | A SwiftUI `@main App` has no clean place to exit before `NSApplication`; links AppKit and needs a GUI session anyway on some hosts; mixes a dev mode into the shipped app |
| C | `gleaner index --home <home>` in the command | One tool for agents | Breaks the ruling that the command never indexes or writes the registry; one mistyped run without `--home` writes the person's real library |
| **D** | **A dev executable `gleaner-index --home <home>`, beside `gleaner-spike`, not bundled** | No GUI, no bundle: `swift run gleaner-index --home <h>`; CI can run it; the command's read-only contract and the ruling stay as they are | One more target; must not drift from the app's setup (below) |

## Built: D

- **Target.** `Sources/gleaner-index/main.swift`, an executable on `GleanerCore` and ArgumentParser only. Not in `bundle-app.sh` or a release; documented as a development tool in the README's layout list.
- **No drift.** Move the setup the app does by hand into `GleanerCore`: `Indexer(folders: LibraryFolders, home: URL?)`, which makes the folders, opens `Registry(path:)` and sets `home`. `LibraryModel.init()` and `gleaner-index` both call it, so they can't set up the indexer differently.
- **Same run.** It runs `indexer.run(providers: all − registry.sourcesOff())`, as `reindex()` does, once, and exits. A library a later Gleaner opened is refused by `Registry.Failure.newer` as the app refuses it; an older one is backed up and upgraded as the app does.
- **Never the person's library.** `--home` is required, with no default; a home that resolves to `NSHomeDirectory()` is refused before anything is opened, so it can't write `~/Library/Application Support/Gleaner` or read `~/.claude` and `~/.codex`.
- **Output.** One JSON object on stdout: the library's `index` after the run (id, generation, `scanned_at`, and each source's status in `Catalog.Source`'s form), and the run's `logs_read`, `new_deliveries` and `new_observations`. A failure is `{"error": {"message"}}`, with the message on stderr too. Exit 0 when the run completed, 1 when the library couldn't be opened or the run failed, 2 for usage. `--now <ISO 8601>` pins the run's clock, as the tests' `run(now:)` does, so a world's results repeat.
- **Tests** (`Tests/GleanerCommandTests/IndexToolTests.swift`). The built `gleaner-index` indexes the command tests' home; its deliveries match a copy indexed in-process by `Indexer(folders:)`, and `gleaner find` reads the library. It refuses no `--home`, your own home and a malformed `--now` (exit 2), and a library a later Gleaner opened (exit 1, unchanged).
- **E0.** Its preparation stays on the app (ruled 2026-10-19): `gleaner-index` would change what preparation costs are charged to G. E0's locked results stay as they are.
- **Query core.** "The app keeps sole ownership of indexing" now names `gleaner-index` as the one other indexer, on a synthetic home only.
