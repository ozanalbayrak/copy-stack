import AppKit
import CopyStackCore
import SwiftUI

/// Settings window: permission banner, snippet list on the left, editor on the right.
struct SettingsView: View {
    @ObservedObject var store: SnippetStore
    let hotKeyManager: HotKeyManager

    @State private var selectedID: Snippet.ID?
    @State private var isTrusted = AccessibilityGate.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            if !isTrusted {
                permissionBanner
            }
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
                editor
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        // The user grants permission in System Settings and comes back; re-check then.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = AccessibilityGate.isTrusted
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Pasting requires Accessibility permission.")
            Spacer()
            Button("Open System Settings") {
                AccessibilityGate.openSystemSettings()
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.25))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.snippets) { snippet in
                    Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                        .tag(snippet.id)
                }
            }
            Divider()
            HStack(spacing: 0) {
                Button {
                    selectedID = store.add().id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add snippet")
                Divider().frame(height: 16)
                Button {
                    if let id = selectedID {
                        store.remove(id: id)
                        selectedID = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .help("Remove snippet")
                .disabled(selectedID == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let id = selectedID, store.snippets.contains(where: { $0.id == id }) {
            SnippetEditor(snippet: binding(for: id), store: store, hotKeyManager: hotKeyManager)
                .id(id)
        } else {
            Text("Select or add a snippet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func binding(for id: Snippet.ID) -> Binding<Snippet> {
        Binding(
            get: { store.snippets.first { $0.id == id } ?? Snippet(id: id, name: "") },
            set: { store.update($0) })
    }
}

/// Edits one snippet. Every change goes straight to the store; there is no Save button.
struct SnippetEditor: View {
    @Binding var snippet: Snippet
    @ObservedObject var store: SnippetStore
    let hotKeyManager: HotKeyManager
    @State private var shortcutError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Name") {
                TextField("Name", text: $snippet.name)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Shortcut") {
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRecorderView(
                        combo: snippet.shortcut,
                        onRecordingChanged: { isRecording in
                            hotKeyManager.isEnabled = !isRecording
                        },
                        onRecord: { combo in
                            do {
                                try store.validate(combo, for: snippet.id)
                                snippet.shortcut = combo
                                shortcutError = nil
                                return true
                            } catch SnippetStore.ValidationError.shortcutConflict(let ownerName) {
                                shortcutError = "Already used by “\(ownerName)”"
                            } catch SnippetStore.ValidationError.reserved {
                                shortcutError = "⌘V is reserved — CopyStack uses it to paste"
                            } catch SnippetStore.ValidationError.missingModifier {
                                shortcutError = "Add ⌘, ⌃ or ⌥ — ⇧ alone can't be a global shortcut"
                            } catch {
                                shortcutError = error.localizedDescription
                            }
                            return false
                        },
                        onClear: {
                            snippet.shortcut = nil
                            shortcutError = nil
                        })
                    .fixedSize()
                    if let shortcutError {
                        Text(shortcutError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Text("Text")
                .font(.headline)
            TextEditor(text: $snippet.text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color(nsColor: .separatorColor))
        }
        .padding()
    }
}
