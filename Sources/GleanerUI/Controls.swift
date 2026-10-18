import AppKit
import SwiftUI

/// Where a control sits decides its size, as in first-party Mac apps: the place's own size for a
/// control that stands on its own, the small size for one beside the fact it acts on. Buttons
/// stay the system's bordered buttons; links and quiet commands are text.
public enum ControlRole: Sendable {
    /// At the head or foot of a view: the detail's Open and Show in Finder, a page's switch, an
    /// empty state's way out, a sheet's buttons. The size the place gives it: regular in a
    /// window, small in a grouped form, as System Settings draws its switches. The default, so it
    /// is rarely written.
    case standalone
    /// Beside the one fact or row it acts on: Compare, Copy, Join, Undo, a row's switch. Small,
    /// so the row keeps the height of its text.
    case inline
}

extension View {
    /// Sizes the controls inside for their role.
    public func controlRole(_ role: ControlRole) -> some View {
        modifier(ControlRoleModifier(role: role))
    }
}

struct ControlRoleModifier: ViewModifier {
    var role: ControlRole

    /// A standalone control is left to its place: a grouped form sizes its own switches without
    /// saying so in the environment, so any size set here would override it.
    @ViewBuilder func body(content: Content) -> some View {
        switch role {
        case .standalone: content
        case .inline: content.controlSize(.small)
        }
    }
}

/// An on/off setting, drawn as the system's switch. Its label is for VoiceOver; on screen, the
/// words beside it say what it switches.
public struct Switch: View {
    public var label: String
    @Binding public var isOn: Bool
    public var role: ControlRole

    public init(_ label: String, isOn: Binding<Bool>, role: ControlRole = .standalone) {
        self.label = label
        _isOn = isOn
        self.role = role
    }

    public var body: some View {
        Toggle(isOn: $isOn) { Text(label) }
            .toggleStyle(.switch)
            .labelsHidden()
            .controlRole(role)
    }
}

/// The three states of a control you can act on: at rest, under the pointer, and pressed. Hover
/// only confirms what the control already says; nothing needed is hover-only. Each text control
/// draws its look from its state, so the gallery can draw the states no pointer reaches.
enum Feedback: CaseIterable, Sendable {
    case rest, hover, press
}

/// A link: ink with a standing underline, never the accent's blue, which marks only what waits on
/// the person. Under the pointer the underline darkens and the pointer is a hand; pressed, the
/// link dims, as a plain Mac button does.
public struct LinkButton: View {
    public var title: String
    public var action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(TextButtonStyle(.link))
    }
}

/// Text that acts, with no bezel: a link, or a command said quietly beside what it acts on. The
/// pointer is a hand over either; hover eases in at the feedback duration.
struct TextButtonStyle: ButtonStyle {
    enum Kind: Sendable {
        /// Goes somewhere: ink with a standing underline that darkens under the pointer.
        case link
        /// A small command in secondary text that takes the label ink under the pointer.
        case quiet
    }

    var kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        Look(kind: kind, configuration: configuration)
    }

    /// The look in each state. Pressed, either dims, as a plain Mac button does.
    @ViewBuilder static func face(_ kind: Kind, _ label: some View, _ state: Feedback, _ contrast: ColorSchemeContrast) -> some View {
        switch kind {
        case .link:
            let rest = Color(nsColor: contrast == .increased ? .secondaryLabelColor : .tertiaryLabelColor)
            label
                .underline(true, color: state == .rest ? rest : .primary)
                .foregroundStyle(.primary)
                .opacity(state == .press ? 0.6 : 1)
        case .quiet:
            label
                .foregroundStyle(state == .rest ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .opacity(state == .press ? 0.6 : 1)
        }
    }

    struct Look: View {
        var kind: Kind
        var configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            TextButtonStyle.face(kind, configuration.label, configuration.isPressed ? .press : hovering ? .hover : .rest, contrast)
                .contentShape(Rectangle())
                .pointerStyle(.link)
                .onHover { hovering in withAnimation(Motion.feedback(reduceMotion)) { self.hovering = hovering } }
        }
    }
}

/// Shows the rest of a list in place, or hides it again: "3 More" or "Show Fewer", said quietly,
/// with a chevron that points where the list goes. The chevron is the standing cue that it is a
/// command and not a count; at rest it reads in secondary text, as the list's own notes do.
public struct MoreButton: View {
    public var hidden: Int
    @Binding public var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(hidden: Int, expanded: Binding<Bool>) {
        self.hidden = hidden
        _expanded = expanded
    }

    public var body: some View {
        Button {
            withAnimation(Motion.state(reduceMotion)) { expanded.toggle() }
        } label: {
            Self.label(hidden: hidden, expanded: expanded)
        }
        .buttonStyle(TextButtonStyle(.quiet))
    }

    static func label(hidden: Int, expanded: Bool) -> some View {
        HStack(spacing: 3) {
            Text(expanded ? "Show Fewer" : "\(hidden) More")
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .imageScale(.small)
                .fontWeight(.semibold)
                .accessibilityHidden(true)
        }
    }
}

/// A command that copies text, then says "Copied" in its place for a moment, with the done mark:
/// the word carries the result, the mark repeats it. Both labels take the same room, so nothing
/// beside it moves; a second click starts the moment again.
public struct CopyButton: View {
    public var title: String
    public var text: String
    public var copy: (String) -> Void
    @State private var copied: Bool
    @State private var reset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, text: String, copy: @escaping (String) -> Void) {
        self.init(title: title, text: text, copied: false, copy: copy)
    }

    /// Starts in the copied state, as the gallery draws it.
    init(title: String, text: String, copied: Bool, copy: @escaping (String) -> Void) {
        self.title = title
        self.text = text
        self.copy = copy
        _copied = State(initialValue: copied)
    }

    public var body: some View {
        Button {
            copy(text)
            withAnimation(Motion.state(reduceMotion)) { copied = true }
            announce("Copied")
            reset?.cancel()
            reset = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.state(reduceMotion)) { copied = false }
            }
        } label: {
            ZStack {
                Label { Text("Copied") } icon: { GlyphView(glyph: .done, size: 13) }.opacity(copied ? 1 : 0)
                Text(title).opacity(copied ? 0 : 1)
            }
        }
        .onDisappear { reset?.cancel() }
    }
}

/// The sentence behind a short label, one click away: a popover, also in the help tag and read
/// by VoiceOver, so nothing needed is hover-only.
public struct InfoButton: View {
    public var text: String
    @State private var shown = false

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").imageScale(.small)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(text)
        .accessibilityLabel("More Info")
        .accessibilityValue(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(Space.m)
        }
    }
}
