import AppKit
import os

/// Pastes text into the frontmost app by briefly borrowing the system
/// pasteboard: snapshot → write text → ⌘V → restore.
///
/// Requests are queued so back-to-back triggers don't interleave their
/// snapshot/restore steps. Main thread only.
final class Paster {
    private typealias ItemSnapshot = [NSPasteboard.PasteboardType: Data]

    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval
    private var queue: [String] = []
    private var isPasting = false

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "Paster")
    private static let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

    init(pasteboard: NSPasteboard = .general, restoreDelay: TimeInterval = 0.15) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
    }

    func paste(_ text: String) {
        guard AccessibilityGate.isTrusted else {
            // Without the grant CGEvent.post is a silent no-op; make the
            // failure visible instead.
            Self.logger.warning("Paste skipped: Accessibility permission not granted")
            AccessibilityGate.requestIfNeeded()
            return
        }
        queue.append(text)
        drain()
    }

    private func drain() {
        guard !isPasting, !queue.isEmpty else { return }
        isPasting = true
        let text = queue.removeFirst()

        let snapshot = snapshotPasteboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()

        // Give the target app time to read the pasteboard before restoring.
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [weak self] in
            guard let self else { return }
            self.restore(snapshot)
            self.isPasting = false
            self.drain()
        }
    }

    // MARK: Pasteboard snapshot

    private func snapshotPasteboard() -> [ItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            var data: ItemSnapshot = [:]
            for type in item.types {
                if let bytes = item.data(forType: type) {
                    data[type] = bytes
                }
            }
            return data.isEmpty ? nil : data
        }
    }

    private func restore(_ snapshot: [ItemSnapshot]) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { data -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, bytes) in data {
                if !item.setData(bytes, forType: type) {
                    Self.logger.error("Failed to restore pasteboard type \(type.rawValue, privacy: .public)")
                }
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    // MARK: Keystroke

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else {
            Self.logger.error("Failed to create ⌘V events")
            return
        }
        // Explicit flags: modifiers the user is still holding from the
        // hotkey (⌃⌥…) must not leak into the paste keystroke.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
