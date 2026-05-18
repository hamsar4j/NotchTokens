//
//  NotchTokensApp.swift
//  NotchTokens
//
//  Created by Hamsaraj S on 18/5/26.
//

import AppKit

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
    private let monitor = UsageMonitor()
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchPanelController(monitor: monitor)
        panelController = controller
        controller.show()
        monitor.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
