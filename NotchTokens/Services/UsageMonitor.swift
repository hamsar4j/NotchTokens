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
            Task { @MainActor [weak self] in
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
            async let limitsTask: ClaudeLimitFetch = claudeUsage.fetchLimits()

            let pricing = await pricingFetcher.current()
            let reader = LocalUsageReader(pricing: pricing)
            var snapshot = reader.readSnapshot()
            let claudeLimits = await limitsTask

            if let index = snapshot.providers.firstIndex(where: { $0.kind == .claude }) {
                snapshot.providers[index].limitStatus = claudeLimits.statusMessage
                if !claudeLimits.limits.isEmpty {
                    snapshot.providers[index].limits = claudeLimits.limits
                }
                if snapshot.providers[index].state == .empty {
                    snapshot.providers[index].state = .ready
                }
            }

            for index in snapshot.providers.indices {
                let provider = snapshot.providers[index]
                guard
                    let budget = currentSettings.budget(for: provider.kind),
                    budget > 0
                else { continue }

                let percent = min(100, (provider.costWindowCost / budget) * 100)
                let reset = budgetWindowReset(for: provider.kind)
                snapshot.providers[index].limits.append(
                    LimitWindow(name: budgetWindowName(for: provider.kind), usedPercent: percent, resetsAt: reset)
                )
                if snapshot.providers[index].state == .empty {
                    snapshot.providers[index].state = .ready
                }
            }

            let refreshedSnapshot = snapshot
            await MainActor.run { [weak self, refreshedSnapshot] in
                self?.snapshot = refreshedSnapshot
            }
        }
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
