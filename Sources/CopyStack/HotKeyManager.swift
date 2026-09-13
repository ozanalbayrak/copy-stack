import AppKit
import Carbon
import Combine
import CopyStackCore
import os

/// Registers one Carbon global hotkey per snippet that has a shortcut and
/// calls `onTrigger` when one fires. Re-registers everything whenever the
/// store changes; snippet counts are small enough that diffing isn't worth it.
final class HotKeyManager {
    /// Set to `false` while the shortcut recorder is capturing keys so the
    /// pressed combo doesn't trigger a paste.
    var isEnabled = true

    private let store: SnippetStore
    private let onTrigger: (Snippet) -> Void
    private var registrations: [UInt32: (ref: EventHotKeyRef, snippetID: Snippet.ID)] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var cancellable: AnyCancellable?

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "HotKeyManager")
    private static let signature: OSType = 0x4350_5354 // "CPST"

    init(store: SnippetStore, onTrigger: @escaping (Snippet) -> Void) {
        self.store = store
        self.onTrigger = onTrigger
        installHandler()
        // @Published emits the current value on subscription, so this also
        // performs the initial registration.
        cancellable = store.$snippets.sink { [weak self] snippets in
            self?.register(snippets)
        }
    }

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    // MARK: Carbon plumbing

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(hotKeyID: hotKeyID.id)
            return noErr
        }, 1, &eventType, userData, &handlerRef)
        if status != noErr {
            Self.logger.error("InstallEventHandler failed: \(status)")
        }
    }

    private func handle(hotKeyID: UInt32) {
        guard isEnabled,
              let registration = registrations[hotKeyID],
              let snippet = store.snippets.first(where: { $0.id == registration.snippetID })
        else { return }
        onTrigger(snippet)
    }

    private func register(_ snippets: [Snippet]) {
        unregisterAll()
        for snippet in snippets {
            guard let combo = snippet.shortcut else { continue }
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(
                combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registrations[id] = (ref, snippet.id)
            } else {
                // Typically the combo is already taken by another app.
                Self.logger.error("RegisterEventHotKey failed for \(combo.displayString, privacy: .public): \(status)")
            }
        }
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }
}
