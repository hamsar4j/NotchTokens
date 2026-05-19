//
//  UsageModels.swift
//  NotchTokens
//

import Foundation

nonisolated enum ProviderKind: String {
    case claude
    case codex
    case opencode

    var assetName: String {
        switch self {
        case .claude: "claudecode-color"
        case .codex: "codex"
        case .opencode: "opencode"
        }
    }
}

nonisolated enum ProviderState: Equatable {
    case ready
    case missing
    case empty
    case failed(String)
}

nonisolated struct UsageSnapshot {
    var providers: [ProviderUsage]

    static let placeholder = UsageSnapshot(providers: [
        .placeholder(kind: .claude, title: "Claude Code"),
        .placeholder(kind: .codex, title: "Codex"),
        .placeholder(kind: .opencode, title: "OpenCode"),
    ])
}

nonisolated struct ProviderUsage {
    let kind: ProviderKind
    var title: String
    var state: ProviderState
    var totalTokens: Int64
    var todayTokens: Int64
    var lastActivity: Date?
    var limits: [LimitWindow]
    var limitStatus: String? = nil
    var cost: Double
    var todayCost: Double
    var costWindowCost: Double
    var costWindowLabel: String = "this month"

    static func placeholder(kind: ProviderKind, title: String) -> ProviderUsage {
        ProviderUsage(
            kind: kind,
            title: title,
            state: .empty,
            totalTokens: 0,
            todayTokens: 0,
            lastActivity: nil,
            limits: [],
            cost: 0,
            todayCost: 0,
            costWindowCost: 0,
            costWindowLabel: "this month"
        )
    }
}

nonisolated struct LimitWindow: Equatable {
    var name: String
    var usedPercent: Double
    var resetsAt: Date?
}
