import AppKit
import GleanerCore
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
                Divider()
                if let model { CollectionMenu().environment(model) }
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Look") { model?.toggleQuickLook() }
                    .keyboardShortcut("y")
                    .disabled(model?.canHandOver != true)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Sources…") { model?.place = .sources }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Gleaner Help") { NSWorkspace.shared.open(URL(string: "https://github.com/lesPrivilege/gleaner#readme")!) }
            }
        }
    }
}

/// The File menu's collections: New Collection where the window is, Add to Collection and Remove
/// from Collection for the works chosen, and Rename and Delete for the collection shown.
struct CollectionMenu: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        let works = model.selectedWorks
        let unit = model.currentUnit
        Button("New Collection") {
            if let place = model.newUnitPlace { model.startNewUnit(in: place.project, inside: place.parent) }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(model.newUnitPlace == nil)
        Menu("Add to Collection") {
            if let project = works.first?.project {
                CollectionChoices(project: project, except: Set(works.compactMap(\.unit))) { unit in
                    Task { await model.add(works, to: unit) }
                } new: {
                    model.startNewUnit(in: project, adding: works.map(\.id))
                }
            }
        }
        .disabled(works.isEmpty)
        Button("Remove from Collection") { Task { await model.remove(works) } }
        .disabled(!works.contains { $0.unit != nil })
        Button("Rename Collection") { if let unit { model.startRenaming(unit) } }
            .disabled(unit == nil)
        Button("Delete Collection") { if let unit { Task { await model.delete(unit) } } }
            .disabled(unit == nil)
    }
}
