import Combine
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the Settings window can show and change
/// whether CopyStack starts at login.
///
/// Only meaningful for the bundled app (`CopyStack.app`); `register()` throws
/// when run from a bare `swift run` binary.
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status

    var isEnabled: Bool {
        status == .enabled
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    /// Registers or unregisters the login item, then re-reads the status.
    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
