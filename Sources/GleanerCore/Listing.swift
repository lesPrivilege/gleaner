import Foundation

extension Artifact.Kind {
    /// Whether a person opens files of this kind to look at them (documents, images, audio and
    /// video, pages, models, installers, folders), rather than a program reading them (data, code,
    /// and formats Gleaner can't place). It orders a list; it never decides whether a file enters
    /// the library or which files are one work.
    public var isOpenedByPerson: Bool {
        switch self {
        case .code, .data, .other: false
        case .document, .image, .media, .web, .model, .build, .folder: true
        }
    }
}

/// How a project's files are laid out in a list (docs/design/capture.md, "Order and grouping,
/// without fitting"): what was handed over and what was observed, in one order, with a folder
/// crowded with files of one kind that no reply named itself folded, and the files that share a stem
/// shown together. Kind, stem and folder order and group a list; none of them decides what enters it
/// or which files are one work.
public enum Listing {
    /// One file of a list: a work handed over, or a candidate observed.
    public enum Entry: Sendable, Identifiable {
        case work(Work)
        case candidate(Candidate)

        public var id: String {
            switch self {
            case .work(let work): work.id
            case .candidate(let candidate): candidate.path
            }
        }

        /// The file it shows: a work's newest.
        public var path: String {
            switch self {
            case .work(let work): work.latest.path
            case .candidate(let candidate): candidate.path
            }
        }

        public var kind: Artifact.Kind {
            switch self {
            case .work(let work): work.kind
            case .candidate(let candidate): candidate.kind
            }
        }

        /// Handed over: named by a reply, or in a folder a reply named.
        public var isHandedOver: Bool {
            if case .work = self { true } else { false }
        }

        /// A reply named the file itself: such a file is never folded away. One only handed over in
        /// a folder, or only observed, may be.
        public var isNamed: Bool {
            if case .work(let work) = self { work.deliveries.contains { $0.member == nil } } else { false }
        }

        /// A work's newest delivery; a candidate's latest write.
        public var date: Date? {
            switch self {
            case .work(let work): work.deliveries[0].deliveredAt
            case .candidate(let candidate): candidate.date
            }
        }

        var folder: String { (path as NSString).deletingLastPathComponent }
        var name: String { (path as NSString).lastPathComponent }
    }

    /// A row of a list.
    public enum Row: Sendable {
        case entry(Entry)
        /// Files in one folder that share a stem, shown together, in list order. Showing them
        /// together claims nothing: not that one was made from another, nor that they are one work.
        case together(stem: String, entries: [Entry])
        /// A folder's files of one kind that no reply named itself, when there are many: one row with
        /// their count, opened on demand, in list order.
        case folded(folder: String, kind: Artifact.Kind, entries: [Entry])
    }

    /// Files of one kind in one folder that no reply named itself fold into one row from this many.
    public static let crowded = 12

    /// Handed over before observed; within each, what a person opens before what a program reads;
    /// then newest first, and by path.
    public static func ordered(_ entries: [Entry]) -> [Entry] {
        keyed(entries).map(\.entry)
    }

    /// What ordering and grouping ask of an entry, worked out once for each, not at each comparison.
    private struct Keyed {
        var entry: Entry
        var isHandedOver: Bool
        var isNamed: Bool
        var kind: Artifact.Kind
        var date: Date
        var path: String
        var folder: String
        var name: String

        init(_ entry: Entry) {
            self.entry = entry
            isHandedOver = entry.isHandedOver
            isNamed = entry.isNamed
            kind = entry.kind
            date = entry.date ?? .distantPast
            path = entry.path
            folder = (path as NSString).deletingLastPathComponent
            name = (path as NSString).lastPathComponent
        }
    }

    /// `entries` with their keys, in `ordered` order.
    private static func keyed(_ entries: [Entry]) -> [Keyed] {
        entries.map(Keyed.init).sorted { a, b in
            if a.isHandedOver != b.isHandedOver { return a.isHandedOver }
            if a.kind.isOpenedByPerson != b.kind.isOpenedByPerson { return a.kind.isOpenedByPerson }
            return a.date != b.date ? a.date > b.date : a.path < b.path
        }
    }

    /// `entries` as rows, in `ordered` order. A folder's files of one kind that no reply named
    /// itself (handed over in a folder, or observed) fold into one row when there are `crowded` or
    /// more; a file a reply named never folds. The other files that share a stem with another file of
    /// their folder are shown together, at the place of the first.
    public static func rows(_ entries: [Entry], crowded: Int = crowded) -> [Row] {
        let entries = keyed(entries)
        let kinds = entries.map { $0.isNamed ? nil : $0.folder + "\n" + $0.isHandedOver.description + "\n" + $0.kind.rawValue }
        var crowds: [String: [Entry]] = [:]
        for (entry, key) in zip(entries, kinds) { if let key { crowds[key, default: []].append(entry.entry) } }
        crowds = crowds.filter { $0.value.count >= crowded }
        let crowd = kinds.map { $0.flatMap { crowds[$0] == nil ? nil : $0 } }
        let family = entries.map { $0.folder + "\n" + Search.form(stem($0.name)) }
        var families: [String: [Entry]] = [:]
        for index in entries.indices where crowd[index] == nil { families[family[index], default: []].append(entries[index].entry) }

        var rows: [Row] = [], shown = Set<String>()
        for (index, entry) in entries.enumerated() {
            if let key = crowd[index] {
                if shown.insert("crowd\n" + key).inserted {
                    rows.append(.folded(folder: entry.folder, kind: entry.kind, entries: crowds[key] ?? []))
                }
            } else if let members = families[family[index]], members.count > 1 {
                if shown.insert("stem\n" + family[index]).inserted { rows.append(.together(stem: stem(entry.name), entries: members)) }
            } else {
                rows.append(.entry(entry.entry))
            }
        }
        return rows
    }

    /// A file name's stem: the name before its first dot, so `ep00.mp4`, `ep00.mix.wav` and
    /// `ep00.inputs.json` share `ep00`, and `ov-4x3.svg` and `ov-4x3.png` share `ov-4x3`. A hidden
    /// file's leading dot is part of its name. Two stems are compared as the disk compares names,
    /// without case.
    public static func stem(_ name: String) -> String {
        guard let dot = name.dropFirst().firstIndex(of: ".") else { return name }
        return String(name[..<dot])
    }
}
