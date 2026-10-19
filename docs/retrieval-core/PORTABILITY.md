# Cloud execution experiment

The real shared Swift core, `gleaner`, and `gleaner-index` compile and run in an
unprivileged Linux container. This is an experiment for comparing retrieval
behavior, not a commitment to support a Linux product or evidence of macOS release
readiness. The original baseline is
`2648094610facfd1ae1805f52a9de282043c808f`.

## Runtime and reproducibility

- Official `swift:6.2-jammy`, Swift 6.2.4, x86_64, Ubuntu 22.04; image digest
  `sha256:5db2c7b978a8d00d3a7faa3787c66da7e2f34373c5bd81c13f5cc90ea477ac49`.
- Container packages: `libsqlite3-dev`, `sqlite3`, `pkg-config`; SQLite 3.37.2.
- Tests run as UID 1000, not root, so permission checks remain meaningful.
- Apple `swift-crypto` 3.15.1 supplies the same SHA-256 interface on Linux.
  Existing dependency revisions remain pinned in `Package.resolved`.
- Only the candidate, baseline and synthetic evaluation directories are mounted.
  The existing unrelated workspace repository is not mounted.

The baseline worktree has exactly the mechanical changes in `portability.patch`;
it has no capture/query prototype changes. An independent held-out test may be
added separately, and is not part of that patch. The patch is also retained at
`/tmp/gleaner-portability.patch` in the cloud environment. Its SHA-256 is recorded
in `portable-test-results.json`.

Recreate the runtime from the separate candidate checkout:

```sh
git worktree add --detach ../gleaner-baseline 2648094610facfd1ae1805f52a9de282043c808f
git -C ../gleaner-baseline apply ../gleaner-cloud/docs/retrieval-core/portability.patch
mkdir -p /workspace/gleaner-evaluation
docker run -d --name gleaner-swift \
  -v /workspace/gleaner-cloud:/workspace/gleaner-cloud \
  -v /workspace/gleaner-baseline:/workspace/gleaner-baseline \
  -v /workspace/gleaner-evaluation:/workspace/gleaner-evaluation \
  -w /workspace/gleaner-cloud \
  swift@sha256:5db2c7b978a8d00d3a7faa3787c66da7e2f34373c5bd81c13f5cc90ea477ac49 \
  sleep infinity
docker exec gleaner-swift sh -c 'apt-get update -qq && apt-get install -y -qq libsqlite3-dev sqlite3 pkg-config'
docker exec gleaner-swift useradd -m -u 1000 gleaner
docker exec gleaner-swift runuser -u gleaner -- swift test -j 4
docker exec -w /workspace/gleaner-baseline gleaner-swift runuser -u gleaner -- swift test -j 4
```

This cloud network required its public CA bundle for Git HTTPS inside the
container. Copying `/etc/ssl/certs/ca-certificates.crt` to the container and setting
`GIT_SSL_CAINFO` to that copy solved verification; certificate verification was
never disabled. Ordinary networks do not need this environment-specific step.

Binary invocation for synthetic benchmarks uses the same runtime:

```sh
docker exec gleaner-swift runuser -u gleaner -- /workspace/gleaner-cloud/.build/debug/gleaner --help
docker exec gleaner-swift runuser -u gleaner -- /workspace/gleaner-baseline/.build/debug/gleaner --help
```

## Explicit portability boundary

macOS keeps its original targets, CryptoKit, UTType, Darwin metadata, FSEvents and
attributed Markdown parser. Linux excludes the app/UI targets, `LogWatcher` and
its tests, and the UI-only `MarkdownBlocks` implementation and tests. There is no
dummy watcher or replacement Markdown renderer.

Linux uses a system SQLite module and a conservative extension/package table.
Unknown file types remain unknown. POSIX metadata uses native Linux fields;
creation time is **unknown**, because portable `stat` does not supply it. Metadata
change time is never treated as creation time. Linux cannot validate macOS
case-insensitive path aliases or the `/private` layout. A Linux ownership wrapper
replaces only the unavailable Objective-C autorelease pool. The explicit array
conversion in `Organization` resolves a Swift 6.2 overload without changing its
contents or ordering.

## Executed checks and limits

Both baseline and candidate executables built. The baseline full suite executed
324 tests: 306 passed, 18 failed with 25 issues. The candidate full run executed
342 tests: 322 passed, 20 failed with 27 issues. The extra two failures were
prototype command-test expectations: a negative argument needed `--offset=-1`,
and an unknown-tool sentinel had become a newly supported tool. Focused rerun
results are reported separately after those repairs; the machine-readable record
preserves the actual full runs.

Final checkpoint rerun at implementation commit `44624ba` plus the independently
authored held-out test: **346 tests, 328 passed, 18 failed with 25 issues**, 6.831
seconds. The failed test names exactly match the baseline's 18. All added tests
and CLI/MCP checks pass in this Linux execution boundary. This rerun does not turn
the native compatibility failures into passes.

The shared 18 failing tests concern unavailable creation dates, case-sensitive
paths, macOS aliases/system folders, and SQLite's ability to read a checkpointed
database without WAL sidecars. The full Linux suite is therefore **not green**.
These are documented compatibility differences, not passing macOS checks. The
machine-readable report lists exact test names and issue counts.

Native validation remains necessary on an authorized Mac checkout: `swift test`
without Linux exclusions, then the documented synthetic benchmark and app-level
checks for packages, file dates, path aliases, permissions, FSEvents and Markdown
presentation. No real library or private source is needed. UI, signing,
notarization, updater and release gates are outside this experiment.

Primary runtime references: [Swift Linux installation](https://www.swift.org/install/linux/),
[official Swift Docker packaging](https://github.com/swiftlang/swift-docker),
[Apple Swift Crypto](https://github.com/apple/swift-crypto).
