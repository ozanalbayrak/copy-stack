import AppKit
import CopyStackCore
import SwiftUI

/// Settings window: permission banner, snippet list on the left, editor on the right.
struct SettingsView: View {
    @ObservedObject var store: SnippetStore
    let hotKeyManager: HotKeyManager
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var accessibility: AccessibilityStatus

    @State private var selectedID: Snippet.ID?
    @State private var loginItemError: String?

    var body: some View {
        VStack(spacing: 0) {
            if !accessibility.isTrusted {
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
        // The view is built at launch, before any permission was granted, so
        // re-check whenever it is shown and whenever the app comes back to
        // the front (the user returns from System Settings).
        .onAppear {
            accessibility.refresh()
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
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
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { enabled in
                        do {
                            try loginItem.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                        }
                    }))
                if loginItem.status == .requiresApproval {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approve in System Settings → Login Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") {
                            LoginItemManager.openSystemSettings()
                        }
                        .font(.caption)
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)
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
    /// Local copy of the toggle so a failed `setSecret` can revert it.
    @State private var isSecret: Bool
    @State private var secretError: String?
    /// Secret text while revealed; `nil` means masked.
    @State private var revealedText: String?
    /// Debounced write of the revealed text; see `scheduleCommit`.
    @State private var pendingCommit: Task<Void, Never>?

    init(snippet: Binding<Snippet>, store: SnippetStore, hotKeyManager: HotKeyManager) {
        _snippet = snippet
        _store = ObservedObject(wrappedValue: store)
        self.hotKeyManager = hotKeyManager
        _isSecret = State(initialValue: snippet.wrappedValue.isSecret)
    }

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
            LabeledContent("Storage") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Store in Keychain", isOn: $isSecret)
                        .onChange(of: isSecret) { _, newValue in
                            // Also fires when a failed attempt reverts the
                            // toggle; the guard makes that a no-op.
                            guard newValue != snippet.isSecret else { return }
                            flushPendingCommit()
                            do {
                                try store.setSecret(newValue, for: snippet.id)
                                secretError = nil
                                revealedText = nil
                            } catch {
                                isSecret = snippet.isSecret
                                secretError = Self.message(for: error)
                            }
                        }
                    if let secretError {
                        Text(secretError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Text("Text")
                .font(.headline)
            if snippet.isSecret {
                secretTextArea
            } else {
                TextEditor(text: $snippet.text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(Color(nsColor: .separatorColor))
            }
        }
        .padding()
        .onDisappear { flushPendingCommit() }
    }

    @ViewBuilder
    private var secretTextArea: some View {
        if let revealedText {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: Binding(
                    get: { revealedText },
                    set: { newValue in
                        self.revealedText = newValue
                        scheduleCommit(newValue)
                    }))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(Color(nsColor: .separatorColor))
                Button("Hide") {
                    // Clear a stale caption first so a failed flush stays visible.
                    secretError = nil
                    flushPendingCommit()
                    self.revealedText = nil
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Hidden — stored in Keychain")
                    .foregroundStyle(.secondary)
                Button("Reveal") {
                    do {
                        revealedText = try store.text(for: snippet.id)
                        secretError = nil
                    } catch {
                        secretError = Self.message(for: error)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color(nsColor: .separatorColor))
        }
    }

    /// Commits ~300 ms after the last keystroke so a revealed edit costs one
    /// Keychain round-trip per pause, not one per character.
    private func scheduleCommit(_ text: String) {
        pendingCommit?.cancel()
        pendingCommit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            commit(text)
        }
    }

    /// Writes any not-yet-committed edit immediately.
    private func flushPendingCommit() {
        guard pendingCommit != nil else { return }
        pendingCommit?.cancel()
        pendingCommit = nil
        if let revealedText {
            commit(revealedText)
        }
    }

    private func commit(_ text: String) {
        pendingCommit = nil
        do {
            try store.setText(text, for: snippet.id)
            secretError = nil
        } catch {
            secretError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case SecretStoreError.accessDenied:
            return "Keychain access was denied"
        case SecretStoreError.failure(let status):
            return "Keychain error \(status)"
        default:
            return error.localizedDescription
        }
    }
}
