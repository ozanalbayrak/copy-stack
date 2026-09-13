import AppKit
import CopyStackCore
import SwiftUI

@main
struct CopyStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("CopyStack", systemImage: "doc.on.clipboard") {
            MenuBarView(store: appDelegate.store, paster: appDelegate.paster)
        }
    }
}

/// Owns the long-lived objects. SwiftUI scenes read them through the adaptor.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SnippetStore()
    let paster = Paster()
    lazy var hotKeyManager = HotKeyManager(store: store) { [paster] snippet in
        paster.paste(snippet.text)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry. Info.plist sets
        // LSUIElement for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        _ = hotKeyManager // register shortcuts at launch
        AccessibilityGate.requestIfNeeded()
    }
}
