//
//  UsageMonitor.swift
//  NotchTokens
//

import Foundation

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

    init(settings: SettingsStore) {
        self.settings = settings
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let claudeUsage = self.claudeUsage
        let pricingFetcher = self.pricingFetcher
        let currentSettings = settings.settings
        Task.detached(priority: .utility) {
            async let _: Void = pricingFetcher.refreshIfStale()
            async let limitsTask: [LimitWindow] = claudeUsage.fetchLimits()

            let pricing = await pricingFetcher.current()
            let reader = LocalUsageReader(pricing: pricing)
            var snapshot = reader.readSnapshot()
            let limits = await limitsTask

            if !limits.isEmpty,
               let index = snapshot.providers.firstIndex(where: { $0.kind == .claude }) {
                snapshot.providers[index].limits = limits
                if snapshot.providers[index].state == .empty {
                    snapshot.providers[index].state = .ready
                }
            }

            for index in snapshot.providers.indices {
                let provider = snapshot.providers[index]
                guard
                    provider.limits.isEmpty,
                    let budget = currentSettings.monthlyBudget(for: provider.kind),
                    budget > 0
                else { continue }

                let percent = min(100, (provider.monthCost / budget) * 100)
                let reset = startOfNextMonth()
                snapshot.providers[index].limits = [
                    LimitWindow(name: "Month", usedPercent: percent, resetsAt: reset)
                ]
                if snapshot.providers[index].state == .empty {
                    snapshot.providers[index].state = .ready
                }
            }

            await MainActor.run { [weak self] in
                self?.snapshot = snapshot
            }
        }
    }
}

private nonisolated func startOfNextMonth() -> Date? {
    let cal = Calendar.current
    let now = Date()
    let components = cal.dateComponents([.year, .month], from: now)
    guard let startOfThisMonth = cal.date(from: components) else { return nil }
    return cal.date(byAdding: .month, value: 1, to: startOfThisMonth)
}
