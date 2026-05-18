//
//  Settings.swift
//  NotchTokens
//

import Foundation

nonisolated struct Settings: Codable, Equatable, Sendable {
    var codexBudget: Double?
    var opencodeBudget: Double?

    static let `default` = Settings(codexBudget: nil, opencodeBudget: nil)

    func monthlyBudget(for kind: ProviderKind) -> Double? {
        switch kind {
        case .claude: nil
        case .codex: codexBudget
        case .opencode: opencodeBudget
        }
    }
}
