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
/// without fitting"): what was handed over and what was observed, in one order, with a crowded
/// folder of one kind folded and the files that share a stem shown together. Kind, stem and folder
/// order and group a list; none of them decides what enters it or which files are one work.
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

        public var isHandedOver: Bool {
            if case .work = self { true } else { false }
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
        /// A folder's observed files of one kind, when there are many: one row with their count,
        /// opened on demand, newest first.
        case folded(folder: String, kind: Artifact.Kind, candidates: [Candidate])
    }

    /// Observed files of one kind in one folder fold into one row from this many.
    public static let crowded = 12

    /// Handed over before observed; within each, what a person opens before what a program reads;
    /// then newest first, and by path.
    public static func ordered(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            if a.isHandedOver != b.isHandedOver { return a.isHandedOver }
            if a.kind.isOpenedByPerson != b.kind.isOpenedByPerson { return a.kind.isOpenedByPerson }
            let (x, y) = (a.date ?? .distantPast, b.date ?? .distantPast)
            return x != y ? x > y : a.path < b.path
        }
    }

    /// `entries` as rows, in `ordered` order. A folder's observed files of one kind fold into one
    /// row when there are `crowded` or more; what was handed over never folds. The other files that
    /// share a stem with another file of their folder are shown together, at the place of the first.
    public static func rows(_ entries: [Entry], crowded: Int = crowded) -> [Row] {
        let entries = ordered(entries)
        var crowds: [String: [Candidate]] = [:]
        for case .candidate(let candidate) in entries {
            crowds[(candidate.path as NSString).deletingLastPathComponent + "\n" + candidate.kind.rawValue, default: []].append(candidate)
        }
        crowds = crowds.filter { $0.value.count >= crowded }
        func crowd(_ entry: Entry) -> String? {
            guard case .candidate = entry else { return nil }
            let key = entry.folder + "\n" + entry.kind.rawValue
            return crowds[key] == nil ? nil : key
        }
        func family(_ entry: Entry) -> String { entry.folder + "\n" + Search.form(stem(entry.name)) }
        let families = Dictionary(grouping: entries.filter { crowd($0) == nil }, by: family)

        var rows: [Row] = [], shown = Set<String>()
        for entry in entries {
            if let key = crowd(entry) {
                if shown.insert("crowd\n" + key).inserted {
                    rows.append(.folded(folder: entry.folder, kind: entry.kind, candidates: crowds[key] ?? []))
                }
            } else if let members = families[family(entry)], members.count > 1 {
                if shown.insert("stem\n" + family(entry)).inserted { rows.append(.together(stem: stem(entry.name), entries: members)) }
            } else {
                rows.append(.entry(entry))
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
