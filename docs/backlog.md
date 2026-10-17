# Pre-release backlog

Work items for the v0.1 release, highest impact first. Each one is finished when its check passes, `swift test` passes, and it is pushed to main. Strike items through as they land.

1. ~~**Dark mode and Increase Contrast.** `Palette` uses fixed light colors, so attention and lost panels are unreadable in dark mode. Use dynamic system colors. Check: the app in dark appearance.~~ Landed; dark appearance still to be looked at by the owner.
2. ~~**Requests that are pasted text.** Some stored "requests" are pasted terminal output or a Codex attachment header ("# Files mentioned by the user: …"), so rows lead with noise. Strip those wrappers in `RequestText.clean` and bump `extractorVersion`. Check: on real data, the rows that showed this now show the person's words.~~ Landed: only Codex's attachment header was noise (6 rows); long `#` requests are work orders the owner pasted and stay.
3. ~~**Markdown parsing in core, with tests.** Move `MarkdownPreview.parse` into GleanerCore as plain blocks and cover headings, nested lists, tables, code blocks and images-as-alt-text with unit tests.~~ Landed; image URLs are also stripped so nothing can fetch them.
4. **Row cost.** `ResultRow` calls `FileManager.fileExists` on every render. Compute existence once per load or reindex.
5. **Accessibility labels.** Give result rows, delivery rows and the drag tile one spoken summary each (name, project, date, status). Check: Accessibility Inspector.
6. **Version and About.** Take the version from the latest git tag in `scripts/bundle-app.sh`, and show it in the About panel.
7. **Release package.** `scripts/release.sh` builds, ad-hoc signs and zips `Gleaner.app` into `build/`, and the README says how to install and what is read. Notarization needs the owner's Developer ID and stays with them.

Open gates that stay with the owner: Gate 1 labeling (`out/candidates.tsv`, `out/recall-sample.md`).
