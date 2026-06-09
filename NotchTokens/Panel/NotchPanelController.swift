//
//  NotchPanelController.swift
//  NotchTokens
//

import AppKit

@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private var currentSize = CGSize(width: 340, height: 68)

    init(monitor: UsageMonitor, onOpenSettings: @escaping () -> Void) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.hasShadow = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar

        panel.contentView = NotchUsagePanelView(
            monitor: monitor,
            onSizeChange: { [weak self] size in
                self?.resize(to: size)
            },
            onOpenSettings: onOpenSettings
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

    func close() {
        panel.orderOut(nil)
    }

    private func resize(to size: CGSize, animated: Bool = true) {
        currentSize = size

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        let targetFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

        guard animated else {
            panel.setFrame(targetFrame, display: true, animate: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0.24, 1.0)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    @objc private func screenParametersChanged() {
        resize(to: currentSize, animated: false)
    }
}
