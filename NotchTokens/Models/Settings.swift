//
//  Settings.swift
//  NotchTokens
//

import Foundation

/// How the usage UI is presented. `.auto` picks the notch panel on Macs with a notch,
/// otherwise the menu-bar item.
nonisolated enum DisplayMode: String, Codable, Sendable, CaseIterable {
    case auto
    case notch
    case menuBar
}

nonisolated struct Settings: Codable, Equatable, Sendable {
    /// Default usage percentage at which a provider is flagged as nearing its limit.
    static let defaultAlertThreshold: Double = 80

    var codexBudget: Double?
    var opencodeBudget: Double?
    var showClaude: Bool
    var showCodex: Bool
    var showOpenCode: Bool
    /// Peak usage % at or above which the warning glyph shows and a notification fires.
    var alertThreshold: Double
    /// Whether to post a system notification when a provider crosses `alertThreshold`.
    var notificationsEnabled: Bool
    /// Notch panel vs menu-bar item (or auto-detect).
    var displayMode: DisplayMode

    static let `default` = Settings(
        codexBudget: nil,
        opencodeBudget: nil,
        showClaude: true,
        showCodex: true,
        showOpenCode: true
    )

    init(
        codexBudget: Double?,
        opencodeBudget: Double?,
        showClaude: Bool = true,
        showCodex: Bool = true,
        showOpenCode: Bool = true,
        alertThreshold: Double = Settings.defaultAlertThreshold,
        notificationsEnabled: Bool = true,
        displayMode: DisplayMode = .auto
    ) {
        self.codexBudget = codexBudget
        self.opencodeBudget = opencodeBudget
        self.showClaude = showClaude
        self.showCodex = showCodex
        self.showOpenCode = showOpenCode
        self.alertThreshold = alertThreshold
        self.notificationsEnabled = notificationsEnabled
        self.displayMode = displayMode
    }

    private enum CodingKeys: String, CodingKey {
        case codexBudget
        case opencodeBudget
        case showClaude
        case showCodex
        case showOpenCode
        case alertThreshold
        case notificationsEnabled
        case displayMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codexBudget = try container.decodeIfPresent(Double.self, forKey: .codexBudget)
        opencodeBudget = try container.decodeIfPresent(Double.self, forKey: .opencodeBudget)
        showClaude = try container.decodeIfPresent(Bool.self, forKey: .showClaude) ?? true
        showCodex = try container.decodeIfPresent(Bool.self, forKey: .showCodex) ?? true
        showOpenCode = try container.decodeIfPresent(Bool.self, forKey: .showOpenCode) ?? true
        alertThreshold =
            try container.decodeIfPresent(Double.self, forKey: .alertThreshold)
            ?? Settings.defaultAlertThreshold
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .auto
    }

    func budget(for kind: ProviderKind) -> Double? {
        switch kind {
        case .claude: nil
        case .codex: codexBudget
        case .opencode: opencodeBudget
        }
    }

    func isVisible(_ kind: ProviderKind) -> Bool {
        switch kind {
        case .claude: showClaude
        case .codex: showCodex
        case .opencode: showOpenCode
        }
    }
}
