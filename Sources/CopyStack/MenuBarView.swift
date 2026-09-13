import AppKit
import CopyStackCore
import SwiftUI

/// Content of the menu bar dropdown.
struct MenuBarView: View {
    @ObservedObject var store: SnippetStore
    let paster: Paster
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.snippets.isEmpty {
            Text("No snippets yet")
        } else {
            ForEach(store.snippets) { snippet in
                Button(Self.title(for: snippet)) {
                    paster.paste(snippet.text)
                }
            }
        }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            // Accessory apps don't come forward on their own.
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: .command)
        Button("Quit CopyStack") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    static func title(for snippet: Snippet) -> String {
        guard let shortcut = snippet.shortcut else { return snippet.name }
        return "\(snippet.name)  —  \(shortcut.displayString)"
    }
}
