import AppKit
import SwiftUI
import Testing
@testable import GleanerUI

/// Every component of GleanerUI on one sheet, drawn by the real views in a window off screen,
/// once for each appearance: light, dark, and Increase Contrast in each. A control that only
/// shows its hover or press under a real pointer is drawn in each state from the face it draws
/// for that state. Runs only when `GLEANER_GALLERY` names a folder for the pictures:
///
///     GLEANER_GALLERY=<folder> swift test --filter GalleryTests
@MainActor @Suite struct GalleryTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["GLEANER_GALLERY"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    enum Look: String, CaseIterable {
        case light, dark, contrastLight = "contrast-light", contrastDark = "contrast-dark"

        var appearance: NSAppearance.Name {
            switch self {
            case .light: .aqua
            case .dark: .darkAqua
            case .contrastLight: .accessibilityHighContrastAqua
            case .contrastDark: .accessibilityHighContrastDarkAqua
            }
        }

        var title: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .contrastLight: "Increase Contrast, light"
            case .contrastDark: "Increase Contrast, dark"
            }
        }

        var increased: Bool { self == .contrastLight || self == .contrastDark }
    }

    @Test(.enabled(if: folder != nil)) func drawEveryComponent() async throws {
        let out = try #require(Self.folder)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for look in Look.allCases {
            let appearance = try #require(NSAppearance(named: look.appearance))
            let sheet = Gallery(look: look)
                .environment(\._colorSchemeContrast, look.increased ? .increased : .standard)
                // Increase Contrast turns on Reduce Transparency with it, as System Settings does.
                .environment(\._accessibilityReduceTransparency, look.increased)
            let host = NSHostingView(rootView: sheet)
            host.appearance = appearance
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView = host
            window.orderBack(nil)
            try await Self.snapshot(window, to: out.appendingPathComponent("gallery-\(look.rawValue).png"))
            window.close()
        }
    }

    /// Lets the main run loop draw and lay out the window.
    static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// The window's content as it draws on screen, its background laid down first (TourTests).
    static func snapshot(_ window: NSWindow, to url: URL) async throws {
        for _ in 0..<12 {
            spin(0.05)
            await Task.yield()
        }
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (window.appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: view.bounds.size).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

/// The sheet: each aspect of the library as a section, in the library's own section style.
struct Gallery: View {
    var look: GalleryTests.Look

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("GleanerUI").font(.largeTitle.weight(.semibold))
                Text(look.title).font(.title3).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    MarksSection()
                    BrandSection()
                    StatusSection()
                    DiffSection()
                    TokensSection(look: look)
                }
                .frame(width: 760)
                VStack(alignment: .leading, spacing: Space.xxl) {
                    ControlsSection()
                    FeedbackSection()
                    SurfacesSection()
                    MotionSection()
                    LayoutSection()
                }
                .frame(width: 520)
            }
        }
        .padding(Space.xxl)
        .fixedSize()
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A section with a caption on its heading line.
struct Part<Content: View>: View {
    var title: String
    var caption: String
    @ViewBuilder var content: Content

    var body: some View {
        DetailSection(title: title, trailing: { Text(caption).font(.callout).foregroundStyle(.secondary) }) {
            content.padding(.top, Space.xs)
        }
    }
}

/// A small name under or beside a sample.
struct Name: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

struct MarksSection: View {
    let columns = Array(repeating: GridItem(.fixed(70), spacing: Space.s, alignment: .top), count: 10)

    var body: some View {
        Part(title: "Marks", caption: "24-point grid, 1.5 stroke · 32, 16, 11 pt") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                ForEach(Glyph.allCases, id: \.self) { glyph in
                    VStack(spacing: Space.xs) {
                        GlyphView(glyph: glyph, size: 32)
                        HStack(spacing: Space.s) { GlyphView(glyph: glyph, size: 16); GlyphView(glyph: glyph, size: 11) }
                        Name(String(describing: glyph))
                    }
                    .frame(width: 70)
                }
            }
            HStack(alignment: .top, spacing: Space.xl) {
                ForEach([SidebarRowSize.small, .medium, .large], id: \.self) { size in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        GlyphLabel(title: "All Deliveries", glyph: .artifact)
                        GlyphLabel(title: "board", glyph: .folder)
                            .padding(.horizontal, Space.s).padding(.vertical, 3)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.tag + 1))
                            .environment(\.backgroundProminence, .increased)
                            .foregroundStyle(.white)
                        Name("Sidebar, \(String(describing: size))")
                    }
                    .environment(\.sidebarRowSize, size)
                }
            }
            .padding(.top, Space.s)
        }
    }
}

struct BrandSection: View {
    var body: some View {
        Part(title: "Agents, vendors, files", caption: "Own colors when named alone, one ink on rows") {
            HStack(alignment: .top, spacing: Space.xl) {
                ForEach(AgentMark.Agent.allCases, id: \.self) { agent in
                    VStack(spacing: Space.xs) {
                        AgentMark(agent, size: 32, color: true)
                        HStack(spacing: Space.s) { AgentMark(agent, size: 16); AgentMark(agent, size: 11) }
                        Name(agent.name)
                    }
                }
                Divider().frame(height: 64)
                ForEach(["report.md", "deck.pptx", "chart.png", "brief.pdf"], id: \.self) { name in
                    VStack(spacing: Space.xs) {
                        FileIcon(path: name, size: 32)
                        Name(name)
                    }
                }
                VStack(spacing: Space.xs) {
                    FileIcon(path: "board", folder: true, size: 32)
                    Name("board")
                }
            }
            HStack(spacing: Space.l) {
                ForEach(ModelVendor.allCases, id: \.self) { vendor in
                    VStack(spacing: Space.xs) {
                        VendorMark(vendor: vendor, size: 20).foregroundStyle(.secondary)
                        Name(vendor.name)
                    }
                }
            }
            .padding(.top, Space.s)
        }
    }
}

struct StatusSection: View {
    static let words: [Mark: String] = [
        .solid: "Same as delivery 2", .hollow: "As first seen", .dashed: "Not on disk", .na: "Folder",
        .attention: "Changed", .cross: "Lost", .failed: "Can’t read", .awaiting: "Suggested",
        .declined: "Kept apart", .running: "Checking…", .done: "Copied",
    ]

    var body: some View {
        Part(title: "Status", caption: "Mark, label, sentence") {
            Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.s) {
                ForEach(Array(stride(from: 0, to: Mark.allCases.count, by: 3)), id: \.self) { start in
                    GridRow {
                        ForEach(Mark.allCases[start..<min(start + 3, Mark.allCases.count)], id: \.self) { mark in
                            HStack(spacing: Space.s) {
                                StatusLabel(mark: mark, text: Self.words[mark] ?? "")
                                Name(String(describing: mark))
                            }
                        }
                    }
                }
            }
            .font(.callout)
            HStack(alignment: .top, spacing: Space.l) {
                StatusPanel(statement: Statement(mark: .attention, title: "Changed",
                                                 detail: "Not among the deliveries Gleaner found.")) {
                    Button("Compare") {}.controlRole(.inline)
                }
                StatusPanel(statement: Statement(mark: .cross, title: "Lost",
                                                 detail: "Not on disk, no saved copy, and not in git at this path."))
                StatusPanel(statement: Statement(mark: .solid, title: "Same as delivery 2", detail: "The hash matches."))
            }
            .padding(.top, Space.s)
        }
    }
}

struct DiffSection: View {
    static func context(_ n: Int, _ text: String) -> DiffLine {
        DiffLine(kind: .context, oldNumber: n, newNumber: n, text: text)
    }

    static let items: [DiffItem] = [
        .line(context(1, "# Board report")),
        .folded((2...5).map { context($0, "Line \($0)") }),
        .line(DiffLine(kind: .removed, oldNumber: 6, newNumber: nil, text: "Revenue grew 12% in the quarter.",
                       segments: [.init(text: "Revenue grew ", changed: false), .init(text: "12%", changed: true),
                                  .init(text: " in the quarter.", changed: false)])),
        .line(DiffLine(kind: .added, oldNumber: nil, newNumber: 6, text: "Revenue grew 14% in the quarter.",
                       segments: [.init(text: "Revenue grew ", changed: false), .init(text: "14%", changed: true),
                                  .init(text: " in the quarter.", changed: false)])),
        .line(DiffLine(kind: .added, oldNumber: nil, newNumber: 7, text: "Margins held.")),
        .line(context(7, "## Outlook")),
    ]

    var body: some View {
        Part(title: "Comparison", caption: "Courtwork’s change language, as adopted") {
            DiffRows(items: Self.items)
                .padding(Space.m)
                .surface(.page)
        }
    }
}

struct ControlsSection: View {
    @State private var on = true
    @State private var off = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Part(title: "Controls", caption: "Sized by role") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.m) {
                GridRow {
                    Name("Standalone")
                    HStack(spacing: Space.s) {
                        Button("Open") {}
                        Button("Show in Finder") {}
                        Button("Open") {}.disabled(true)
                    }
                }
                GridRow {
                    Name("Inline")
                    HStack(spacing: Space.s) {
                        Button("Compare") {}
                        Button { } label: { Label { Text("Join") } icon: { GlyphView(glyph: .merge, size: 12) } }
                        Button("Keep Apart") {}
                        CopyButton(title: "Copy", text: "") { _ in }
                        CopyButton(title: "Copy", text: "", copied: true) { _ in }
                    }
                    .controlRole(.inline)
                }
                GridRow {
                    Name("Switches")
                    HStack(spacing: Space.m) {
                        Switch("On", isOn: $on, role: .standalone)
                        Switch("Off", isOn: $off, role: .standalone)
                        Switch("On", isOn: $on)
                        Switch("Off", isOn: $off)
                    }
                }
                GridRow {
                    Name("Info")
                    HStack(spacing: Space.xs) {
                        StatusLabel(mark: .attention, text: "Changed")
                        InfoButton(text: "Not among the deliveries Gleaner found.")
                    }
                }
            }
        }
    }
}

struct FeedbackSection: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Part(title: "Hover and press", caption: "Rest · hover · press, 120 ms") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.l, verticalSpacing: Space.m) {
                GridRow {
                    Name("Link")
                    ForEach(Feedback.allCases, id: \.self) { state in
                        TextButtonStyle.face(.link, Text("revenue.png"), state, contrast)
                    }
                }
                GridRow {
                    Name("Quiet")
                    ForEach(Feedback.allCases, id: \.self) { state in
                        TextButtonStyle.face(.quiet, Text("3 More"), state, contrast)
                    }
                }
            }
            .font(.callout)
            HStack(spacing: Space.l) {
                ForEach([false, true], id: \.self) { hovering in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.m) {
                            FileIcon(path: "report.md", size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("report.md").font(.headline)
                                StatusLabel(mark: .solid, text: "Verified").font(.callout)
                            }
                        }
                        .padding(.vertical, Space.xs).padding(.horizontal, Space.s)
                        .background(HoverWash.fill(hovering, contrast), in: RoundedRectangle(cornerRadius: Radius.card))
                        Name(hovering ? "Drag tile, hover" : "Drag tile, rest")
                    }
                }
            }
            .padding(.top, Space.s)
        }
    }
}

struct SurfacesSection: View {
    var body: some View {
        Part(title: "Surfaces", caption: "Glass only floats; Reduce Transparency is opaque") {
            HStack(alignment: .top, spacing: Space.m) {
                sample(.page, "page")
                sample(.awaiting, "awaiting")
                sample(.attention, "attention")
                sample(.lost, "lost")
            }
            HStack(spacing: Space.m) {
                floating(reduce: false)
                floating(reduce: true)
            }
            .padding(.top, Space.s)
        }
    }

    func sample(_ surface: Surface, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Board report").font(.callout)
                .padding(Space.m)
                .frame(width: 112, height: 56, alignment: .topLeading)
                .surface(surface)
            Name(name)
        }
    }

    func floating(reduce: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Revenue grew 12%, ahead of plan. Margins held, and the deck went out on time with the chart.")
                .font(.system(.callout, design: .monospaced))
                .padding(Space.m)
                .frame(width: 244, height: 84, alignment: .topLeading)
                .overlay(alignment: .bottomTrailing) {
                    Text("First 64 KB").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, Space.s).padding(.vertical, 2)
                        .surface(.floating, in: Capsule())
                        .padding(Space.s)
                }
                .surface(.page)
                .environment(\._accessibilityReduceTransparency, reduce)
            Name(reduce ? "floating, Reduce Transparency" : "floating")
        }
    }
}

struct MotionSection: View {
    var body: some View {
        Part(title: "Motion", caption: "None under Reduce Motion; arrivals only fade") {
            HStack(alignment: .bottom, spacing: Space.xl) {
                ForEach(Motion.allCases, id: \.self) { motion in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Curve(motion: motion)
                            .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .background(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 1) }
                            .frame(width: 140 * motion.duration / 0.24, height: 48)
                        Name("\(String(describing: motion)) · \(Int(motion.duration * 1000)) ms")
                    }
                }
            }
        }
    }

    /// The token's easing, its time across and its progress up.
    struct Curve: Shape {
        var motion: Motion

        func path(in rect: CGRect) -> Path {
            let c = motion.curve
            func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
                3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t
            }
            return Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                for step in 1...48 {
                    let t = Double(step) / 48
                    path.addLine(to: CGPoint(x: rect.minX + rect.width * bezier(t, c.x1, c.x2),
                                             y: rect.maxY - rect.height * bezier(t, c.y1, c.y2)))
                }
            }
        }
    }
}

struct TokensSection: View {
    var look: GalleryTests.Look

    /// Each color's value for this sheet, from the palette's own table: an off-screen window can't
    /// take the system's Increase Contrast, which is what picks the contrast values in the app.
    var swatches: [(name: String, color: Color)] {
        Palette.Tone.allCases.map { ($0.rawValue, $0.value(dark: look == .dark || look == .contrastDark, contrast: look.increased)) }
            + [("mark", Palette.mark)]
    }

    var body: some View {
        Part(title: "Space, radius, color", caption: "A 4-point step; tag and card; one role per color") {
            HStack(alignment: .bottom, spacing: Space.l) {
                ForEach([("xs", Space.xs), ("s", Space.s), ("m", Space.m), ("l", Space.l), ("xl", Space.xl), ("xxl", Space.xxl)], id: \.0) { name, value in
                    VStack(spacing: Space.xs) {
                        Rectangle().fill(.tertiary).frame(width: value, height: value)
                        Name("\(name) \(Int(value))")
                    }
                }
                Divider().frame(height: 48)
                ForEach([("tag", Radius.tag), ("card", Radius.card)], id: \.0) { name, value in
                    VStack(spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: value).strokeBorder(.secondary).frame(width: 40, height: 32)
                        Name("\(name) \(Int(value))")
                    }
                }
            }
            HStack(alignment: .top, spacing: Space.s) {
                ForEach(swatches, id: \.name) { item in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: Radius.tag).fill(item.color)
                            .overlay(RoundedRectangle(cornerRadius: Radius.tag).strokeBorder(Color(nsColor: .separatorColor)))
                            .frame(width: 68, height: 28)
                        Name(item.name).fixedSize()
                    }
                    .frame(width: 68, alignment: .leading)
                }
            }
            .padding(.top, Space.s)
        }
    }
}

struct LayoutSection: View {
    var body: some View {
        Part(title: "Sections", caption: "Space and type, not boxes") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s + 2) {
                InfoRow(label: "Agent") {
                    HStack(spacing: Space.s) {
                        AgentMark(.claudeCode, size: 16, color: true)
                        Text("Board review")
                    }
                }
                InfoRow(label: "Model") {
                    HStack(spacing: Space.s) {
                        VendorMark(vendor: .kimi, size: 14).foregroundStyle(.secondary)
                        Text("moonshot/kimi-k2.5")
                        Text("via magpie").foregroundStyle(.secondary)
                    }
                }
                InfoRow("Delivered", "18 Oct 2026 at 09:40")
                InfoRow(label: "Delivered With") {
                    FlowLayout(spacing: Space.m) {
                        ForEach(["revenue.png", "deck.pptx", "brief.pdf"], id: \.self) { LinkButton(title: $0) {} }
                    }
                }
                InfoRow(label: "Relation") {
                    HStack(spacing: Space.s) {
                        AgentMark(.codex, size: 16, color: true)
                        RelationLine(inEffect: true)
                        Text("in effect").foregroundStyle(.secondary)
                        RelationLine(inEffect: false)
                        Text("not").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            EmptyState(title: "No Deliveries Yet", glyph: .artifact, description: "Files an agent names in a reply to you appear here.")
                .frame(height: 160)
        }
    }
}
