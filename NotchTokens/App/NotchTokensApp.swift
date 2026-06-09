//
//  NotchTokensApp.swift
//  NotchTokens
//
//  Created by Hamsaraj S on 18/5/26.
//

import AppKit
import UserNotifications

@main
enum NotchTokensMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        app.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var monitor = UsageMonitor(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(store: settings)
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchPanelController(
            monitor: monitor,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() }
        )
        panelController = controller
        controller.show()
        monitor.refresh()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
