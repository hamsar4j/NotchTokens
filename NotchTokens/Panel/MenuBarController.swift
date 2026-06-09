//
//  MenuBarController.swift
//  NotchTokens
//

import AppKit

/// Menu-bar presentation: an `NSStatusItem` whose button shows a compact summary and, on
/// click, opens a popover hosting the same panel view used by the notch (in embedded mode).
@MainActor
final class MenuBarController {
    private static let contentSize = CGSize(width: 380, height: 292)

    private let monitor: UsageMonitor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let panelView: NotchUsagePanelView

    init(monitor: UsageMonitor, onOpenSettings: @escaping () -> Void) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        panelView = NotchUsagePanelView(
            monitor: monitor,
            embedded: true,
            onSizeChange: { _ in },
            onOpenSettings: onOpenSettings
        )
        panelView.frame = CGRect(origin: .zero, size: Self.contentSize)

        let controller = NSViewController()
        controller.view = panelView
        popover.contentViewController = controller
        popover.contentSize = Self.contentSize
        popover.behavior = .transient

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "NotchTokens usage")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }

        monitor.onSnapshotChange = { [weak self] snapshot in
            self?.panelView.receive(snapshot)
            self?.updateStatusItem(snapshot)
        }
        updateStatusItem(monitor.snapshot)
    }

    func teardown() {
        if popover.isShown { popover.performClose(nil) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            panelView.receive(monitor.snapshot)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem(_ snapshot: UsageSnapshot) {
        guard let button = statusItem.button else { return }
        // Prefer the peak limit % (the "am I near a limit" glance); fall back to today's spend.
        if let peak = snapshot.providers.flatMap(\.limits).map(\.usedPercent).max() {
            button.title = " \(Int(peak.rounded()))%"
        } else {
            let today = snapshot.providers.reduce(0.0) { $0 + $1.todayCost }
            button.title = today > 0 ? " \(formatCost(today))" : ""
        }
    }
}
