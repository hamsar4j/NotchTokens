//
//  NotchTokensApp.swift
//  NotchTokens
//
//  Created by Hamsaraj S on 18/5/26.
//

import AppKit
import Combine
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
    private var notchController: NotchPanelController?
    private var menuBarController: MenuBarController?
    private var activeMode: DisplayMode?
    private var modeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyMode(resolve(settings.settings.displayMode))
        monitor.refresh()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Rebuild the presentation when (only) the display mode changes.
        modeCancellable =
            settings.$settings
            .map(\.displayMode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                self.applyMode(self.resolve(mode))
            }
    }

    /// Resolve `.auto` to a concrete mode: notch panel when the main display has a notch,
    /// otherwise the menu-bar item.
    private func resolve(_ mode: DisplayMode) -> DisplayMode {
        switch mode {
        case .auto:
            let hasNotch = (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
            return hasNotch ? .notch : .menuBar
        case .notch, .menuBar:
            return mode
        }
    }

    private func applyMode(_ resolved: DisplayMode) {
        guard resolved != activeMode else { return }
        activeMode = resolved

        notchController?.close()
        notchController = nil
        menuBarController?.teardown()
        menuBarController = nil

        let openSettings: () -> Void = { [weak self] in self?.settingsWindow.show() }
        switch resolved {
        case .notch:
            let controller = NotchPanelController(monitor: monitor, onOpenSettings: openSettings)
            controller.show()
            notchController = controller
        case .menuBar:
            menuBarController = MenuBarController(monitor: monitor, onOpenSettings: openSettings)
        case .auto:
            break  // resolve() never returns .auto
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
