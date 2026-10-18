import AppKit
import SwiftUI

@main
struct GleanerApp: App {
    @State private var model: LibraryModel?
    @State private var failure: String?

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        do {
            _model = State(initialValue: try LibraryModel())
        } catch {
            _failure = State(initialValue: "\(error)")
        }
    }

    var body: some Scene {
        Window("Gleaner", id: "library") {
            if let model {
                LibraryView()
                    .environment(model)
                    .onAppear { model.start() }
            } else {
                ContentUnavailableView(
                    "Gleaner couldn’t open its library",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure ?? ""))
            }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Check for New Deliveries") { model?.reindex() }
                    .keyboardShortcut("r")
                Divider()
                Button("Open Verified Copy") { model?.openSelected() }
                    .keyboardShortcut("o")
                    .disabled(model?.canHandOver != true)
                Button("Show in Finder") { if let model, let result = model.selected { model.reveal(model.file(in: result)) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model?.selected == nil)
                Button("Copy Path") { if let model, let result = model.selected { model.copyPath(model.file(in: result)) } }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(model?.selected == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Look") { model?.toggleQuickLook() }
                    .keyboardShortcut("y")
                    .disabled(model?.canHandOver != true)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Sources and Storage…") { model?.place = .sources }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Gleaner Help") { NSWorkspace.shared.open(URL(string: "https://github.com/lesPrivilege/gleaner#readme")!) }
            }
        }
    }
}
