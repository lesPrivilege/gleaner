# Native interaction and release maturity

This chapter applies the project-first [composition alternatives](control-panel-explorations.md) to macOS behavior. It is source-based research at `79d724d1228a4b748572958dcbdd22aa6b7da142`, without native rendering or interaction validation. Platform references supply conventions; the Gleaner choices below remain proposals for Opus.

## Arrive, leave and return

Gleaner currently uses a primary SwiftUI `Window`, regular activation and indexing on appearance. Apple distinguishes this single-window scene's close-to-quit behavior from a primary `WindowGroup`. Choose residency deliberately; do not promise that the app remains running after its window closes. [GleanerApp:8–36](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/GleanerApp.swift#L8-L36) · [Apple Window](https://developer.apple.com/documentation/swiftui/window)

Test Close, Hide, Minimize, Quit, Dock activation and Finder relaunch separately. Returning should restore useful project/search context without duplicate windows, stolen focus or automatic handoff. An ordinary windowed app is a valid baseline. Menu-bar access, login launch and a global shortcut are optional conveniences, each with additional lifecycle and accessibility work.

## Source access and interruptions

Explain which sources are read, what remains local and which bytes are retained. Log access and artifact access are different. If a sandboxed distribution is chosen, folder selection and persistent bookmarks are possible mechanisms; stale bookmarks and other access restrictions still need recovery. Neither whole-home scanning nor Full Disk Access follows automatically from the task. [Apple sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

An access flow can remain small: unconfigured → choosing → checking → ready. Cancellation leaves the previous configuration intact; denied, revoked or unavailable access has a source-specific explanation and a feasible Choose Again/Retry. Some current source-enumeration failures return empty results, so “no deliveries” cannot explain every access failure. Cached evidence and saved bytes should remain usable where possible. [ClaudeCodeAdapter:17–24](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/ClaudeCodeAdapter.swift#L17-L24) · [LibraryModel:41–85](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryModel.swift#L41-L85)

Distinguish first scan, cached refresh, empty library, no matches, partial failure, unavailable bytes and failed handoff. No matches suggests clearing search/filter; no configured sources suggests setup. Relevant incomplete coverage needs one contextual signal, not an operations dashboard. A completed scan does not establish extraction recall.

Manual or foreground checking remains a valid option. If watching continues, reconcile source disappearance/reappearance, sleep/wake and relaunch without duplicates; filesystem events need not be a complete account of changes. Quit should stop work, and relaunch should recover committed records. Cancellation should not look like an error or erase usable results.

## Keyboard, menus and exact action targets

Keep Find/search discoverable, arrows within the focused list and normal Tab/Shift-Tab movement. Optional Space-to-preview must not intercept typing or input methods. Escape should affect the active disclosure, preview or operation, with focus returning predictably. Apple recommends discoverable standard commands; preserve ordinary text Copy when evidence text is focused. [Keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards) · [Menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) · [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)

| Action meaning to compare | Proposed contract |
|---|---|
| Open selected delivery | Open its verified copy in the associated app; identify it as a copy and surface failure |
| Show original / saved copy | Reveal the named target, with fallback made explicit |
| Copy original path | Copy location text, which may be unavailable or later refer to changed contents |
| Keep a saved copy | Preserve selected bytes in Gleaner; distinct from an external Save Copy To… destination |
| Drag / Save Copy To… | Offer the chosen payload with its filename and extension, preserving the source |
| Use current file instead | An explicit change of selection that updates preview, actions and accessible name together |

These are meanings, not final labels or a requirement to put six buttons on screen. Current regular-file preview/Open use staged bytes; Copy Path uses the original source; Reveal has fallbacks. The [source review](design-review-evidence.md#3-preview-and-neighboring-actions-refer-to-different-file-roles) details those differences. The existing name “Save a copy” means internal preservation and can stay if its context makes that clear.

Preparation can express selected → checking → preparing → ready / unavailable / failed / cancelled. Old asynchronous work must remain associated with its requesting selection. Current shared staging state, detached work and consumers of any ready URL create a **source-level stale-completion risk**, not a reproduced defect. Hash verification alone does not establish that the UI's selected object is the one offered. [LibraryModel:116–129](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryModel.swift#L116-L129) · [DetailView:106–125, 219–244, 291–306](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift#L106-L306)

Existing-file providers and deferred file promises are different options. Validate the actual receiver before changing mechanisms. Keep staged bytes available through consumption; cancellation preserves originals. Provide a keyboard-accessible takeaway if drag is primary. A completed drag is not proof that a browser upload or agent attachment succeeded. [Apple drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop)

## Preview, maintenance and visual polish

Embedded Quick Look, a detached preview panel, internal text rendering and opening an associated app serve different tasks. No renderer promises all formats. The [preview matrix](control-panel-explorations.md#preview-and-serious-review-are-different-depths) covers selected bytes, unsupported formats, truncated text, HTML dependencies and current folders. A separate panel is optional, not a required third surface.

Source/storage/refresh preferences can live in Settings if needed; content filters stay by the results. About should identify version/build. Help should explain access, copies and observation caveats. If updates are offered, checking/failure/restart states should preserve review context. No updater vendor or channel is selected here. Current ad-hoc signing for local use does not demonstrate distribution launch behavior. [Bundle script:2, 27](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/scripts/bundle-app.sh#L2-L27) · [Apple Settings](https://developer.apple.com/design/human-interface-guidelines/settings) · [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

The useful maturity precedents are narrow: [Maccy navigation](https://github.com/p0deje/Maccy/blob/7e14eb8d4578f1509f9a02e7bfd5c465550695cd/Maccy/Observables/NavigationManager.swift#L31) coordinates selection/accessibility and input state; its [key handler](https://github.com/p0deje/Maccy/blob/7e14eb8d4578f1509f9a02e7bfd5c465550695cd/Maccy/Views/KeyHandlingView.swift#L12) preserves marked-text composition. Itsycal handles [dismissal](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/ViewController.m#L990), [denied access](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/Prefs/PrefsEventsVC.m#L205) and [wake](https://github.com/sfsam/Itsycal/blob/1a31050555a97e3b7aac5470ec147abfe7aa0d6a/Itsycal/ViewController.m#L1480). [CotEditor FolderFinder](https://github.com/coteditor/CotEditor/blob/3de66b63ccab9c4f6fa0d836ffefaacb6b6f754f/CotEditor/Sources/Document%20Window/Sidebar/Folder%20Find/FolderFinder.swift#L170) checks cancellation before publishing search/selection results. These are inspected development snapshots, not tested binaries. Borrow interaction discipline without automatic paste, calendar-specific permissions or a full editor.

Native validation should cover six task groups:

1. Cancel source choice; deny/grant/revoke access and recover. Keep inaccessible originals distinct from usable saved copies.
2. Find one logical project across agents, repositories/worktrees and an external output; clear search without losing orientation.
3. Select an older match, change selection rapidly, refresh and switch apps. Preview/Open/drag must agree on bytes and filename.
4. Exercise unchanged, changed, deleted, saved, first-seen-late, unsupported and truncated states without false success.
5. Complete review/takeaway with keyboard and VoiceOver. Inspect focus, error announcements, light/dark appearance, Increase Contrast, larger text and Reduce Motion. Existing text-plus-symbol statuses are useful; hardcoded colors and the 9-point badge require actual inspection before visual findings. [LibraryView:77–86](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryView.swift#L77-L86) · [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
6. Cancel preparation/scan; close/hide/reopen, sleep/wake and quit/relaunch during work. Check stale publication, duplicates and unintended handoff.

These scenarios supplement the two open product gates recorded in the [entry handoff](README.md#current-evidence-and-limits). They do not claim those gates have passed. Optional conveniences should be judged after the main retrieval and review flow works reliably.
