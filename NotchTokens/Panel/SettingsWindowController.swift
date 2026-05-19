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
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var window: NSWindow!
        let hosting = NSHostingController(rootView: SettingsView(
            store: store,
            onDone: { window?.close() }
        ))
        window = NSWindow(contentViewController: hosting)
        window.title = "NotchTokens Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        .frame(width: 340)
    }
}

private struct BudgetRow: View {
    let label: String
    @Binding var value: Double?

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            TextField(
                "No limit",
                value: $value,
                format: .currency(code: "USD").precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
        }
    }
}
