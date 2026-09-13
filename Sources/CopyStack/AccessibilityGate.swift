import AppKit
import ApplicationServices

/// Wraps the Accessibility (AX) trust check. Posting synthetic ⌘V requires it.
enum AccessibilityGate {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system "would like to control this computer" prompt when
    /// not yet trusted. Returns the current trust state.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
