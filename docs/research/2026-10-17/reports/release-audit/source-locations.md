# Source-location convention

All Gleaner source citations in this review refer to commit **22dd07d926a764f0a2efcdeb093b78f0b9eab41b**. This index resolves abbreviated citations without requiring the separate review checkout.

- A repository-relative path such as `Sources/GleanerCore/Library.swift:227–235` is relative to the [pinned repository root](https://github.com/lesPrivilege/gleaner/tree/22dd07d926a764f0a2efcdeb093b78f0b9eab41b). Its GitHub URL is `https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/<path>#L227-L235`; a single line uses `#L227`. Comma-separated ranges identify separate locations in the same file.
- A bare Swift filename resolves through the table below. `Locator.sha256:78–85` denotes the `sha256` function in `Sources/GleanerCore/Locator.swift`, lines 78–85.
- `structure.md` means [docs/design/structure.md](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/docs/design/structure.md). `CHANGELOG.md` means the [repository-root changelog](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/CHANGELOG.md). Other paths beginning `docs/`, `Sources/`, `Tests/`, or `scripts/` are repository-relative. The acceptance commands use the [scripts directory](https://github.com/lesPrivilege/gleaner/tree/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/scripts) and [Tests/GleanerCoreTests](https://github.com/lesPrivilege/gleaner/tree/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Tests/GleanerCoreTests).
- `report.md`, `evidence-appendix.md`, `native-acceptance.md`, `process-log.md`, and paths beginning `probes/` or `evidence/` are relative to this review package. Example fixture names such as `report.md`, `guide.md`, and `diagram.png` in scenarios are synthetic inputs, not repository citations.
- Files in `message-parts/` are text transmission chunks, not independently rendered documents. Reassemble chunks in manifest order for each source and resolve relative links from the package root.

| Abbreviated code citation | Pinned source file |
|---|---|
| `ClaudeCodeAdapter.swift` | [Sources/GleanerCore/ClaudeCodeAdapter.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/ClaudeCodeAdapter.swift) |
| `CodexAdapter.swift` | [Sources/GleanerCore/CodexAdapter.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/CodexAdapter.swift) |
| `ComparePane.swift` | [Sources/Gleaner/ComparePane.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/ComparePane.swift) |
| `Comparison.swift` | [Sources/GleanerCore/Comparison.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Comparison.swift) |
| `ContentStore.swift` | [Sources/GleanerCore/ContentStore.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/ContentStore.swift) |
| `DetailView.swift` | [Sources/Gleaner/DetailView.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/DetailView.swift) |
| `GleanerApp.swift` | [Sources/Gleaner/GleanerApp.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/GleanerApp.swift) |
| `Indexer.swift` | [Sources/GleanerCore/Indexer.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Indexer.swift) |
| `Library.swift` | [Sources/GleanerCore/Library.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Library.swift) |
| `LibraryModel.swift` | [Sources/Gleaner/LibraryModel.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/LibraryModel.swift) |
| `LibraryView.swift` | [Sources/Gleaner/LibraryView.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/LibraryView.swift) |
| `Locator.swift` | [Sources/GleanerCore/Locator.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Locator.swift) |
| `LogWatcher.swift` | [Sources/GleanerCore/LogWatcher.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/LogWatcher.swift) |
| `MarkdownBlocks.swift` | [Sources/GleanerCore/MarkdownBlocks.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/MarkdownBlocks.swift) |
| `MarkdownPreview.swift` | [Sources/Gleaner/MarkdownPreview.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/MarkdownPreview.swift) |
| `MentionExtractor.swift` | [Sources/GleanerCore/MentionExtractor.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/MentionExtractor.swift) |
| `Projects.swift` | [Sources/GleanerCore/Projects.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Projects.swift) |
| `Registry.swift` | [Sources/GleanerCore/Registry.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/Registry.swift) |
| `SessionLog.swift` | [Sources/GleanerCore/SessionLog.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/SessionLog.swift) |
| `SettingsView.swift` | [Sources/Gleaner/SettingsView.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/SettingsView.swift) |
| `TextDiff.swift` | [Sources/GleanerCore/TextDiff.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/GleanerCore/TextDiff.swift) |
| `Wording.swift` | [Sources/Gleaner/Wording.swift](https://github.com/lesPrivilege/gleaner/blob/22dd07d926a764f0a2efcdeb093b78f0b9eab41b/Sources/Gleaner/Wording.swift) |

Evidence classifications remain as recorded: `historical-file-current-directory` is a direct branch trace; project-resolution probes are Python transcriptions, not executed Swift. SQLite, Git and shell checks executed their respective implementations. The ASCII fence-pattern check ran in Python; proposed Swift regression checks remain uncompiled and unrun.
