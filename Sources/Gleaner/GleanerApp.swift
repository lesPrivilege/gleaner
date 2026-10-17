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
            CommandGroup(after: .newItem) {
                Button("Check for New Deliveries") { model?.reindex() }
                    .keyboardShortcut("r")
            }
        }
    }
}
