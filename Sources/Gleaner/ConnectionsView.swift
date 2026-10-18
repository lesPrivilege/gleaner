import GleanerCore
import GleanerUI
import SwiftUI

/// Each agent Gleaner reads, as a connection the person can see and switch: its mark, how its logs
/// last read, and a switch. Off, Gleaner neither reads nor watches the agent's logs and shows none
/// of its deliveries; nothing is removed, and on again shows it all. Shown in the toolbar's
/// popover, as a menu-bar app shows its connections, and at the top of each agent's page.
struct ConnectionRow: View {
    @Environment(LibraryModel.self) private var model
    var provider: Provider
    var size: CGFloat = 28

    var body: some View {
        let on = !model.sourcesOff.contains(provider)
        let state = Self.state(provider, in: model)
        HStack(spacing: Space.s + 2) {
            AgentMark(provider: provider, size: size, color: true)
                .saturation(on ? 1 : 0).opacity(on ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(Wording.provider(provider)).fontWeight(.semibold)
                StatusLabel(mark: state.0, text: state.1, size: 11).font(.caption)
            }
            Spacer(minLength: Space.s)
            Switch("Read \(Wording.provider(provider))", isOn: Binding(get: { on }, set: { value in Task { await model.setSource(provider, on: value) } }))
                .help(on ? "Stop reading \(Wording.provider(provider))’s logs and hide its deliveries" : "Read \(Wording.provider(provider))’s logs again")
        }
    }

    /// An agent's state in a word or two: off, reading, or how its logs last read.
    static func state(_ provider: Provider, in model: LibraryModel) -> (Mark, String) {
        if model.sourcesOff.contains(provider) { return (.na, "Off") }
        if let source = model.sources?[provider] { return Wording.source(source) }
        return model.indexed ? (.dashed, "Not read") : (.running, "Reading…")
    }
}

/// The toolbar's sources button: the agent mark, with the triangle when one needs a look, opening
/// the connections popover.
struct ConnectionsButton: View {
    @Environment(LibraryModel.self) private var model
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Label {
                Text("Sources")
            } icon: {
                GlyphView(glyph: model.logTrouble == nil ? .agent : .warning, size: 16)
                    .foregroundStyle(model.logTrouble == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.attention))
            }
        }
        .help(model.logTrouble ?? "Sources: the agents Gleaner reads")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            ConnectionsPanel { shown = false }
        }
    }
}

/// The agents and their switches, with the way to the full Sources page.
struct ConnectionsPanel: View {
    @Environment(LibraryModel.self) private var model
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Sources").font(.headline)
            ForEach(Provider.allCases, id: \.self) { provider in
                ConnectionRow(provider: provider)
            }
            Divider()
            HStack {
                Button("Sources…") { model.place = .sources; close() }
                Spacer()
                Button("Check Now") { model.reindex() }
                    .disabled(model.sourcesOff.count == Provider.allCases.count)
            }
            .controlRole(.inline)
        }
        .padding(Space.l)
        .frame(width: 320)
    }
}

/// An agent's connection drawn as the relation grammar draws one: the agent, the provider it sends
/// requests to when its logs name one, and the vendors of the models that wrote its replies, on one
/// line. The line is solid while Gleaner reads the agent, dashed while it is off: not in effect.
struct TopologyLine: View {
    @Environment(LibraryModel.self) private var model
    var provider: Provider

    var body: some View {
        let on = !model.sourcesOff.contains(provider)
        let models = model.models(of: provider)
        let gateways = Array(Set(models.compactMap(\.provider))).sorted()
        let vendors = Self.vendors(models)
        HStack(spacing: Space.s) {
            AgentMark(provider: provider, size: 20, color: true).saturation(on ? 1 : 0)
            ForEach(gateways, id: \.self) { gateway in
                RelationLine(inEffect: on)
                Text(gateway).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, Space.s).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                    .help("The provider \(Wording.provider(provider)) sent requests to")
            }
            RelationLine(inEffect: on)
            if vendors.isEmpty {
                Text(models.isEmpty ? "No deliveries yet" : "Models not named in the logs").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: Space.xs + 2) {
                    ForEach(vendors.prefix(4), id: \.self) { VendorMark(vendor: $0, size: 16) }
                    if vendors.count > 4 { Text("+\(vendors.count - 4)").font(.caption).foregroundStyle(.secondary) }
                }
                .foregroundStyle(on ? .primary : .tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Wording.provider(provider)), \(on ? "connected" : "off")" +
                            (gateways.isEmpty ? "" : ", through \(gateways.joined(separator: ", "))") +
                            (vendors.isEmpty ? "" : ", models by \(vendors.map(\.name).joined(separator: ", "))"))
    }

    /// The vendors of the models, the most-used first, each once.
    static func vendors(_ models: [(provider: String?, model: String?, deliveries: Int)]) -> [ModelVendor] {
        var seen: [ModelVendor] = []
        for vendor in models.compactMap({ ModelVendor.of(model: $0.model) }) where !seen.contains(vendor) { seen.append(vendor) }
        return seen
    }
}
