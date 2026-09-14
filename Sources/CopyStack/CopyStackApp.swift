import AppKit
import CopyStackCore
import os
import SwiftUI

@main
struct CopyStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: appDelegate.store, paste: appDelegate.paste)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        // A `Settings` scene is never auto-presented; a lone `Window` scene
        // would open itself at launch (and be restored on relaunch).
        Settings {
            SettingsView(
                store: appDelegate.store,
                hotKeyManager: appDelegate.hotKeyManager,
                loginItem: appDelegate.loginItem,
                accessibility: appDelegate.accessibility)
        }
    }
}

/// Owns the long-lived objects. SwiftUI scenes read them through the adaptor.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SnippetStore()
    let paster = Paster()
    let loginItem = LoginItemManager()
    let accessibility = AccessibilityStatus()
    lazy var hotKeyManager = HotKeyManager(store: store) { [weak self] snippet in
        self?.paste(snippet)
    }

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry. Info.plist sets
        // LSUIElement for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        _ = hotKeyManager // register shortcuts at launch
        AccessibilityGate.requestIfNeeded()
    }

    /// Resolves the snippet's text (Keychain for secret ones) and pastes it.
    /// A Keychain failure, or a secret with no stored text, is logged and
    /// nothing is pasted.
    func paste(_ snippet: Snippet) {
        let text: String
        do {
            text = try store.text(for: snippet.id)
        } catch {
            Self.logger.error("Could not read text for \(snippet.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        if snippet.isSecret && text.isEmpty {
            Self.logger.warning("Secret snippet \(snippet.name, privacy: .public) has no stored text; nothing to paste")
            return
        }
        paster.paste(text)
    }
}
