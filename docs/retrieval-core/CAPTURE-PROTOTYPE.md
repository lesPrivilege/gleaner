# Capture prototype: controlled feasibility evidence

This is an exploratory extractor change, not an approved capture architecture or a claim of improved task success. Baseline: `2648094610facfd1ae1805f52a9de282043c808f`. All new fixtures are synthetic.

## Behavior under test

- Recognize a relative folder written as `out/`; existing folder listing still decides membership.
- Expand explicit finite filename ranges, such as `part{01..03}.md` or `shot07–shot09.png` (also an em dash), with a maximum of 256 members. Preserve the original target, reply excerpt and native evidence anchors for each candidate.
- Reject unsupported unencoded `*` and `?` wildcard targets, rather than manufacture missing originals; encoded literal metacharacters remain possible. Reject NUL-containing paths. Document fragments are separated before wildcard checks.
- Keep ordinary hyphenated names and abbreviated Unicode year spans literal. Keep ambiguous duplicated relative paths unchanged; current file existence is not proof of the intended path.

Expansion is textual. It performs no directory scan, shell expansion or source execution, and supplies no new authorship or historical-membership evidence. This does not solve narrative folder-plus-range shorthand or general wildcard discovery.

## Design conflict requiring a ruling

The opening of [capture.md](../design/capture.md) explicitly replaces earlier drafts about “reading folder-and-range shorthand in replies” and “finding episodes by numbered names” because they fit one case. Its architecture instead separates final-reply deliveries from session workspace observations. [SPEC §9](../SPEC.md#9-extraction) also excludes placeholders rather than declaring finite range syntax.

Consequently, retain range expansion as a controlled hypothesis pending a broader relevance corpus and an explicit design ruling. Relative-folder recognition and wildcard rejection can be evaluated independently. Passing these tests does not establish that range parsing is the next production priority, that a repeated-stem filename always denotes a range, or that capture coverage yields useful first results.

`Registry.extractorVersion` remains **20**. These checks use direct extraction and a fresh temporary registry. Existing indexed logs are not automatically reread for these changes; no migration, durable-correction preservation across a version bump, or upgraded-library claim is made here.

## Executed evidence

- Swift typechecking of the shared extractor and its direct dependencies passed on Linux.
- The same [extractor-only smoke source](../../eval/retrieval/extractor-smoke.swift) passed **4/10 baseline cases** and **10/10 prototype cases**. Results: [baseline JSON](../../eval/retrieval/results/capture-baseline.json), [prototype JSON](../../eval/retrieval/results/capture-candidate.json). Baseline failures cover relative folders, brace ranges, repeated-stem ranges, wildcard literals, NUL rejection and oversized ranges. These are extraction assertions; they do not apply admission, build a catalog or measure logical-object relevance.
- The portability worker executed all **10 `CaptureRetrievalTests` successfully** in the candidate package run. The additional suite covers admission, evidence retention, renamed project/stem/extension cases, repeated evidence, missing originals, honest backfill provenance, and unchanged first captures after rereading an edited original. This is Linux execution; macOS/APFS validation remains separate.

No Finder comparison, held-out generalization result, first-layer precision, task-relevant recall, expansion-effort improvement or resource/latency conclusion follows from this smoke test.

## Reproduction

Run from the repository root with a Swift 6 toolchain. This compiles the actual extractor files directly; it has no replacement search or extraction implementation and needs no package dependencies.

```sh
capture_scratch=$(mktemp -d)
git show 2648094610facfd1ae1805f52a9de282043c808f:Sources/GleanerCore/MentionExtractor.swift > "$capture_scratch/MentionExtractor.swift"
swiftc Sources/GleanerCore/SessionLog.swift Sources/GleanerCore/Paths.swift Sources/GleanerCore/Redactor.swift "$capture_scratch/MentionExtractor.swift" eval/retrieval/extractor-smoke.swift -o "$capture_scratch/baseline"
swiftc Sources/GleanerCore/SessionLog.swift Sources/GleanerCore/Paths.swift Sources/GleanerCore/Redactor.swift Sources/GleanerCore/MentionExtractor.swift eval/retrieval/extractor-smoke.swift -o "$capture_scratch/candidate"
"$capture_scratch/baseline" > "$capture_scratch/baseline.json"
"$capture_scratch/candidate" > "$capture_scratch/candidate.json"
cat "$capture_scratch/baseline.json" "$capture_scratch/candidate.json"
swift test -j 4 --filter CaptureRetrievalTests
```

The captured smoke ran with the `gleaner-swift` container and `/workspace/gleaner-cloud` mounted; the compiler was Swift 6.2.4 for `x86_64-unknown-linux-gnu`. For that environment, prefix each Swift command with `docker exec -w /workspace/gleaner-cloud gleaner-swift`; container scratch paths must be created/copied inside that container. Package tests run as its non-root `gleaner` user to preserve permission-test semantics.
