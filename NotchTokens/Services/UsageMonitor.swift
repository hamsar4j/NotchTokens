//
//  UsageMonitor.swift
//  NotchTokens
//

import Foundation
import Combine

@MainActor
final class UsageMonitor {
    private(set) var snapshot = UsageSnapshot.placeholder {
        didSet {
            onSnapshotChange?(snapshot)
        }
    }

    var onSnapshotChange: ((UsageSnapshot) -> Void)?

    let settings: SettingsStore

    private let claudeUsage = ClaudeUsageService()
    private let pricingFetcher = PricingFetcher()
    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var baseSnapshot = UsageSnapshot.placeholder
    private var refreshGeneration = 0

    init(settings: SettingsStore) {
        self.settings = settings
        settingsCancellable = settings.$settings.dropFirst().sink { [weak self] settings in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshGeneration += 1
                self.publish(self.baseSnapshot, using: settings)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        refresh(using: settings.settings)
    }

    private func refresh(using currentSettings: Settings) {
        let claudeUsage = self.claudeUsage
        let pricingFetcher = self.pricingFetcher
        refreshGeneration += 1
        let generation = refreshGeneration
        Task.detached(priority: .utility) {
            async let _: Void = pricingFetcher.refreshIfStale()

            let pricing = await pricingFetcher.current()
            let reader = LocalUsageReader(pricing: pricing)
            var snapshot = reader.readSnapshot()

            if currentSettings.showClaude,
               let index = snapshot.providers.firstIndex(where: { $0.kind == .claude }) {
                let claudeLimits = await claudeUsage.fetchLimits()
                snapshot.providers[index].limitStatus = claudeLimits.statusMessage
                if !claudeLimits.limits.isEmpty {
                    snapshot.providers[index].limits = claudeLimits.limits
                }
                if snapshot.providers[index].state == .empty {
                    snapshot.providers[index].state = .ready
                }
            }

            let refreshedSnapshot = snapshot
            await MainActor.run { [weak self, refreshedSnapshot, currentSettings] in
                guard let self, self.refreshGeneration == generation else { return }
                self.publish(refreshedSnapshot, using: currentSettings)
            }
        }
    }

    private func publish(_ baseSnapshot: UsageSnapshot, using settings: Settings) {
        self.baseSnapshot = baseSnapshot
        snapshot = displaySnapshot(from: baseSnapshot, using: settings)
    }

    private func displaySnapshot(from snapshot: UsageSnapshot, using settings: Settings) -> UsageSnapshot {
        var display = snapshot
        display.providers = display.providers.filter { settings.isVisible($0.kind) }

        for index in display.providers.indices {
            let provider = display.providers[index]
            guard
                let budget = settings.budget(for: provider.kind),
                budget > 0
            else { continue }

            let percent = min(100, (provider.costWindowCost / budget) * 100)
            let reset = budgetWindowReset(for: provider.kind)
            display.providers[index].limits.append(
                LimitWindow(name: budgetWindowName(for: provider.kind), usedPercent: percent, resetsAt: reset)
            )
            if display.providers[index].state == .empty {
                display.providers[index].state = .ready
            }
        }

        return display
    }
}

private nonisolated func budgetWindowName(for kind: ProviderKind) -> String {
    switch kind {
    case .claude: "Month"
    case .codex, .opencode: "30d"
    }
}

private nonisolated func budgetWindowReset(for kind: ProviderKind) -> Date? {
    switch kind {
    case .claude: startOfNextMonth()
    case .codex, .opencode: nil
    }
}

private nonisolated func startOfNextMonth() -> Date? {
    let cal = Calendar.current
    let now = Date()
    let components = cal.dateComponents([.year, .month], from: now)
    guard let startOfThisMonth = cal.date(from: components) else { return nil }
    return cal.date(byAdding: .month, value: 1, to: startOfThisMonth)
}
