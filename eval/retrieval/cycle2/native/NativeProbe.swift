import Foundation
@testable import GleanerCore

// Diagnostic executable linked to the actual built core. Synthetic temporary data only.
// It records behavior without changing production code or altering test expectations.
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("gleaner-native-probe-\(UUID().uuidString)")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let started = Date()
var results: [String: Any] = ["uid": getuid(), "started_at": started.timeIntervalSince1970]
func dateValue(_ value: Date?) -> Any { value.map { $0.timeIntervalSince1970 as Any } ?? NSNull() }
func metadata(_ url: URL) throws -> [String: Any] {
    let attrs = try fm.attributesOfItem(atPath: url.path)
    let file = Workspace.file(at: url.path)
    return ["foundation_creation": dateValue(attrs[.creationDate] as? Date),
            "core_creation": dateValue(file?.createdAt), "core_modified": dateValue(file?.modifiedAt),
            "core_changed": dateValue(file?.changedAt)]
}
func write(_ path: String, _ text: String = "synthetic") throws -> URL {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
}

// Same Foundation calls as the fixture helpers; record what the filesystem actually accepted.
let dated = try write("dates/report.md")
let requested = started.addingTimeInterval(-60)
let before = try metadata(dated)
try fm.setAttributes([.creationDate: requested], ofItemAtPath: dated.path)
try fm.setAttributes([.modificationDate: requested], ofItemAtPath: dated.path)
let file = Workspace.file(at: dated.path)!
let span = Span(stretches: [DateInterval(start: started.addingTimeInterval(-120), end: started.addingTimeInterval(60))])
var suppliedBirth = file
suppliedBirth.createdAt = requested
results["birthtime"] = ["requested_creation": requested.timeIntervalSince1970, "before": before,
    "after": try metadata(dated), "set_attributes_returned_without_error": true,
    "observed_with_actual_metadata": Workspace.place(file, in: span)?.rawValue ?? "none",
    "counterfactual_observed_with_known_birth": Workspace.place(suppliedBirth, in: span)?.rawValue ?? "none"]

// The two-delivery test physically creates both files before either future reply.
let appendix = try write("dates/appendix.pdf")
let future = started.addingTimeInterval(4200)
try fm.setAttributes([.creationDate: future], ofItemAtPath: appendix.path)
try fm.setAttributes([.modificationDate: future], ofItemAtPath: appendix.path)
let appendixFile = Workspace.file(at: appendix.path)!
var knownAppendix = appendixFile
knownAppendix.createdAt = future
let firstReply = started.addingTimeInterval(2400), secondReply = started.addingTimeInterval(6000)
results["synthetic_future_birth"] = ["requested_creation": future.timeIntervalSince1970,
    "metadata": try metadata(appendix), "first_reply": firstReply.timeIntervalSince1970,
    "second_reply": secondReply.timeIntervalSince1970,
    "actual_membership_first": Membership.handedOver(appendixFile, deliveredAt: firstReply, grace: 0),
    "actual_membership_second": Membership.handedOver(appendixFile, deliveredAt: secondReply, grace: 0),
    "counterfactual_known_birth_first": Membership.handedOver(knownAppendix, deliveredAt: firstReply, grace: 0)]

// Review freshness can still be checked without inventing a creation date.
let reviewed = try write("review/take.txt", "take one")
// Match ReviewTests' whole-second fixture date, avoiding a separate Foundation
// nanosecond round-trip difference when setAttributes restores modification time.
try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: floor(started.timeIntervalSince1970) - 60)], ofItemAtPath: reviewed.path)
let shown = FileStat(reviewed.path)!
Thread.sleep(forTimeInterval: 0.02)
let handle = try FileHandle(forWritingTo: reviewed)
try handle.write(contentsOf: Data("take two".utf8))
try handle.close()
try fm.setAttributes([.modificationDate: shown.modifiedAt], ofItemAtPath: reviewed.path)
let rewritten = FileStat(reviewed.path)!
let reviewIndexer = Indexer(registry: try Registry(path: root.appendingPathComponent("review/registry.sqlite").path),
    store: ContentStore(objects: root.appendingPathComponent("review/objects"), staging: root.appendingPathComponent("review/staging")),
    sources: LogSources(claudeProjects: root.appendingPathComponent("unused-claude"), codexHome: root.appendingPathComponent("unused-codex")))
var staleReviewRefused = false
do { _ = try reviewIndexer.review(reviewed.path, as: .approved, shown: shown, at: Date()) }
catch Review.Failure.changedSinceShown { staleReviewRefused = true }
results["review_freshness"] = ["shown_creation": dateValue(shown.createdAt),
    "equal_for_persisted_review_state": rewritten == shown,
    "unchanged_for_immediate_approval": rewritten.isUnchanged(since: shown),
    "ctime_changed": rewritten.changedAt != shown.changedAt,
    "stale_review_refused_by_indexer": staleReviewRefused,
    "reviews_written": try reviewIndexer.registry.reviews().count]

// A real alias and a merely different spelling must be distinguished by identity.
let home = root.appendingPathComponent("home")
let lower = try write("home/report.md")
let upper = home.appendingPathComponent("Report.md")
let link = root.appendingPathComponent("linked-home")
try fm.createSymbolicLink(at: link, withDestinationURL: home)
let wrongCaseExists = fm.fileExists(atPath: upper.path)
let wrongCaseIdentity = FileIdentity(upper.path)
let wrongCaseSkip = Workspace.skipped(home.path.uppercased(), home: home.path, own: [])
try Data("different object".utf8).write(to: upper)
results["case_and_alias"] = ["wrong_case_exists_before_creation": wrongCaseExists,
    "wrong_case_identity_before_creation": wrongCaseIdentity != nil,
    "two_spellings_have_same_identity_after_creation": FileIdentity(lower.path) == FileIdentity(upper.path),
    "uppercase_home_exists": fm.fileExists(atPath: home.path.uppercased()),
    "uppercase_home_skip_reason": wrongCaseSkip as Any? ?? NSNull(),
    "symlink_home_skip_reason": Workspace.skipped(link.path, home: home.path, own: []) as Any? ?? NSNull(),
    "symlink_library_skip_reason": Workspace.skipped(link.path + "/Library", home: home.path, own: []) as Any? ?? NSNull()]

let systemPaths = ["/", "/Users", "/var", "/tmp", "/private", "/Applications", "/System/Library", "/usr/local/src", "/Library/Caches"]
results["system_paths"] = Dictionary(uniqueKeysWithValues: systemPaths.map { path in
    (path, ["exists": fm.fileExists(atPath: path), "resolved": Workspace.resolved(path),
            "skip_reason": Workspace.skipped(path, home: home.path, own: []) as Any? ?? NSNull()] as [String: Any])
})
let locked = try write("permissions/locked.txt")
_ = chmod(locked.path, 0)
let noReadStat = FileStat(locked.path) == nil
let locatorKind = Locator.stat(locked.path).kind.rawValue
let noReadHash = Locator.sha256(locked.path) == nil
_ = chmod(locked.path, 0o644)
results["private_and_permissions"] = ["temporary_directory": fm.temporaryDirectory.path,
    "resolved_temporary_has_private_prefix": Workspace.resolved(fm.temporaryDirectory.path).hasPrefix("/private/"),
    "private_exists": fm.fileExists(atPath: "/private"), "can_create_in_root": access("/", W_OK) == 0,
    "textual_private_tmp_normalization": Paths.standard("/private/tmp/synthetic-probe-file"),
    "private_tmp_and_tmp_resolve_equally": Workspace.resolved("/private/tmp") == Workspace.resolved("/tmp"),
    "locked_file_stat_is_nil": noReadStat, "locked_locator_kind": locatorKind, "locked_hash_is_nil": noReadHash]

_ = try write("packages/Demo.app/Contents/Info.plist")
_ = try write("packages/Notes.rtfd/TXT.rtf")
_ = try write("packages/Demo.framework/Headers/Demo.h")
let packageRoot = root.appendingPathComponent("packages")
let packageWalk = Workspace.walk(packageRoot.path)
let appBefore = packageWalk.files.first { $0.path.hasSuffix("/Demo.app") }!
Thread.sleep(forTimeInterval: 0.02)
_ = try write("packages/Demo.app/Contents/Info.plist", "changed nested bytes")
let appAfter = Workspace.walk(packageRoot.path).files.first { $0.path.hasSuffix("/Demo.app") }!
results["packages"] = ["classifications": Dictionary(uniqueKeysWithValues:
    ["Demo.app", "Notes.rtfd", "Demo.framework", "Other.unknown"].map { ($0, Workspace.isPackage($0)) }),
    "package_metadata_unchanged_after_nested_file_rewrite": appBefore == appAfter,
    "walk": packageWalk.files.map { ["relative_path": String($0.path.dropFirst(packageRoot.path.count + 1)),
        "is_package": $0.isPackage, "creation": dateValue($0.createdAt)] as [String: Any] }.sorted {
            ($0["relative_path"] as! String) < ($1["relative_path"] as! String)
        }]

// Do not remove sidecars from a live connection. Create/checkpoint/close, then measure
// a real read-only Catalog connection with and without directory write permission.
func prepareLibrary(_ name: String) throws -> (URL, String) {
    let home = root.appendingPathComponent(name)
    let folders = LibraryFolders(home: home)
    try fm.createDirectory(at: URL(fileURLWithPath: folders.registry).deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        let registry = try Registry(path: folders.registry)
        try registry.db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
    for suffix in ["-wal", "-shm"] where fm.fileExists(atPath: folders.registry + suffix) {
        try fm.removeItem(atPath: folders.registry + suffix)
    }
    return (home, folders.registry)
}
func sidecars(_ path: String) -> [String] { ["-wal", "-shm"].filter { fm.fileExists(atPath: path + $0) } }
var wal: [String: Any] = [:]
for writable in [true, false] {
    let (home, path) = try prepareLibrary(writable ? "wal-writable" : "wal-unwritable")
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    let beforeFiles = sidecars(path)
    if !writable { _ = chmod(parent.path, 0o555) }
    var record: [String: Any] = ["sidecars_before": beforeFiles]
    do {
        let catalog = try Catalog(home: home)
        record["catalog_opened"] = true
        record["artifact_count"] = try catalog.registry.artifacts().count
        record["sidecars_during_read"] = sidecars(path)
        do { try catalog.registry.db.execute("CREATE TABLE probe_forbidden (x INTEGER)"); record["write_refused"] = false }
        catch { record["write_refused"] = true }
        record["database_bytes_unchanged"] = before == (try Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        record["catalog_opened"] = false
        record["error_kind"] = (error as? Catalog.Failure)?.kind ?? "other"
        record["database_bytes_unchanged"] = before == (try Data(contentsOf: URL(fileURLWithPath: path)))
    }
    _ = chmod(parent.path, 0o755)
    record["sidecars_after_close"] = sidecars(path)
    wal[writable ? "writable_parent" : "unwritable_parent"] = record
}
results["readonly_wal"] = wal
let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
