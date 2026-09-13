import AppKit
import os

/// Pastes text into the frontmost app by briefly borrowing the system
/// pasteboard: snapshot → write text → ⌘V → restore.
///
/// Requests are queued so back-to-back triggers don't interleave their
/// snapshot/restore steps. Main thread only.
final class Paster {
    /// One pasteboard item's representations, in the order the item listed them.
    private typealias ItemSnapshot = [(type: NSPasteboard.PasteboardType, data: Data)]

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

        // Pasteboard privacy (macOS 15.4+): reading the pasteboard may prompt
        // the user or be denied outright. A denied read yields no data, so
        // clearing in that state would lose the user's clipboard for good.
        // Skip the paste rather than risk it.
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            Self.logger.error("Pasteboard access is denied; skipping paste to protect the clipboard")
            abortPending()
            return
        }
        let snapshot = snapshotPasteboard()
        if snapshot.isEmpty, !(pasteboard.types ?? []).isEmpty {
            // Content exists but none of it could be read: the read was
            // denied (or failed). A genuinely empty pasteboard has no types.
            Self.logger.error("Pasteboard has content that could not be read; skipping paste to protect the clipboard")
            abortPending()
            return
        }
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

    /// Drops every queued request without touching the pasteboard.
    private func abortPending() {
        queue.removeAll()
        isPasting = false
    }

    // MARK: Pasteboard snapshot

    private func snapshotPasteboard() -> [ItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            var representations: ItemSnapshot = []
            for type in item.types {
                if let bytes = item.data(forType: type) {
                    representations.append((type, bytes))
                }
            }
            return representations.isEmpty ? nil : representations
        }
    }

    private func restore(_ snapshot: [ItemSnapshot]) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            // Same order as the original item: readers that take the first
            // type they understand must see the same representation.
            for (type, bytes) in representations {
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
