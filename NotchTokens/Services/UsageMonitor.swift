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

    private let reader = LocalUsageReader()
    private let claudeUsage = ClaudeUsageService()
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
        let reader = self.reader
        let claudeUsage = self.claudeUsage
        Task.detached(priority: .utility) {
            async let snapshotTask: UsageSnapshot = {
                reader.readSnapshot()
            }()
            async let limitsTask: [LimitWindow] = claudeUsage.fetchLimits()

            var snapshot = await snapshotTask
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
