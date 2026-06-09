//
//  LoginItem.swift
//  NotchTokens
//

import OSLog
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "launch at login" toggle.
/// The system owns the truth; we just read its status and register/unregister.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            Log.app.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
