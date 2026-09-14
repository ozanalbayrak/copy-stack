import AppKit
import Combine

/// Live Accessibility trust state for the Settings window.
///
/// `AXIsProcessTrusted()` is cheap but nobody re-asks it on its own, so a
/// banner that reads it once goes stale the moment the user grants the
/// permission. This refreshes on app activation and on the system-wide
/// notification macOS posts whenever the Accessibility list changes; views
/// also call `refresh()` when they appear.
final class AccessibilityStatus: ObservableObject {
    @Published private(set) var isTrusted = AccessibilityGate.isTrusted

    /// Posted by macOS when an app is added to, removed from, or toggled in
    /// System Settings → Privacy & Security → Accessibility.
    private static let permissionsChanged = Notification.Name("com.apple.accessibility.api")

    private var activationObserver: NSObjectProtocol?
    private var permissionsObserver: NSObjectProtocol?

    init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        permissionsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.permissionsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let permissionsObserver {
            DistributedNotificationCenter.default().removeObserver(permissionsObserver)
        }
    }

    func refresh() {
        let trusted = AccessibilityGate.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }
}
