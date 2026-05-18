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

    private let claudeUsage = ClaudeUsageService()
    private let pricingFetcher = PricingFetcher()
    private var timer: Timer?

    init() {
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

            await MainActor.run { [weak self] in
                self?.snapshot = snapshot
            }
        }
    }
}
