//
//  SettingsWindowController.swift
//  NotchTokens
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private weak var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if let window {
            centerOnScreen(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var window: NSWindow!
        let hosting = NSHostingController(
            rootView: SettingsView(
                store: store,
                onDone: { window?.close() }
            ))
        window = NSWindow(contentViewController: hosting)
        window.title = "NotchTokens Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        centerOnScreen(window)
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerOnScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - windowFrame.width / 2,
            y: visibleFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rolling 30-Day Budgets")
                .font(.headline)
                .foregroundStyle(.secondary)

            BudgetRow(label: "Codex", value: $store.settings.codexBudget)
            BudgetRow(label: "OpenCode", value: $store.settings.opencodeBudget)

            Text("Codex and OpenCode budgets use the last 30 days. Claude Code uses live limits from Anthropic.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("Visible Providers")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Claude Code", isOn: $store.settings.showClaude)
                    Toggle("Codex", isOn: $store.settings.showCodex)
                    Toggle("OpenCode", isOn: $store.settings.showOpenCode)
                }
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Usage Alerts")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Warn at")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $store.settings.alertThreshold, in: 50...100, step: 5)
                    Text("\(Int(store.settings.alertThreshold))%")
                        .font(.body.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }

                Toggle("Notify when a provider crosses the threshold", isOn: $store.settings.notificationsEnabled)
                    .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct BudgetRow: View {
    let label: String
    @Binding var value: Double?

    // Reject negative budgets — clamp anything below zero up to zero.
    private var clamped: Binding<Double?> {
        Binding(
            get: { value },
            set: { value = $0.map { Swift.max(0, $0) } }
        )
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            TextField(
                "No limit",
                value: clamped,
                format: .currency(code: "USD").precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
        }
    }
}
