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
                    .disabled(model?.selectedHandoffURL == nil)
                Button("Show in Finder") { if let a = model?.selected?.artifact { model?.reveal(a) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model?.selected == nil)
                Button("Show in Log") { if let d = model?.selectedDelivery { model?.revealLog(d) } }
                    .disabled(model?.selected == nil)
                Button("Copy Path") { if let a = model?.selected?.artifact { model?.copyPath(a) } }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(model?.selected == nil)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Reference") {
                    if let model, let delivery = model.selectedDelivery { Task { await model.copyReference(delivery) } }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model?.selected == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Look") { model?.toggleQuickLook() }
                    .keyboardShortcut("y")
                    .disabled(model?.selectedHandoffURL == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Gleaner Help") { NSWorkspace.shared.open(URL(string: "https://github.com/lesPrivilege/gleaner#readme")!) }
            }
        }

        Settings {
            if let model {
                SettingsView().environment(model)
            }
        }
    }
}
