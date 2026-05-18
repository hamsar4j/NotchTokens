//
//  NotchPanelController.swift
//  NotchTokens
//

import AppKit

@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private var currentSize = CGSize(width: 220, height: 38)

    init(monitor: UsageMonitor) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.hasShadow = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar

        panel.contentView = NotchUsagePanelView(
            monitor: monitor,
            onSizeChange: { [weak self] size in
                self?.resize(to: size)
            }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        resize(to: currentSize, animated: false)
        panel.orderFrontRegardless()
    }

    private func resize(to size: CGSize, animated: Bool = false) {
        currentSize = size

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        let targetFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

        panel.setFrame(targetFrame, display: true, animate: animated)
    }

    @objc private func screenParametersChanged() {
        resize(to: currentSize, animated: false)
    }
}
