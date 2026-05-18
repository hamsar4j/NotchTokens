//
//  Pricing.swift
//  NotchTokens
//

import Foundation

nonisolated struct ModelRate {
    let input: Double
    let output: Double
    let cachedInput: Double
    let cacheWrite: Double

    static let zero = ModelRate(input: 0, output: 0, cachedInput: 0, cacheWrite: 0)
}

nonisolated enum Pricing {
    private static let claudeRates: [(String, ModelRate)] = [
        ("opus-4", ModelRate(input: 15.0, output: 75.0, cachedInput: 1.50, cacheWrite: 18.75)),
        ("opus", ModelRate(input: 15.0, output: 75.0, cachedInput: 1.50, cacheWrite: 18.75)),
        ("sonnet-4", ModelRate(input: 3.0, output: 15.0, cachedInput: 0.30, cacheWrite: 3.75)),
        ("sonnet", ModelRate(input: 3.0, output: 15.0, cachedInput: 0.30, cacheWrite: 3.75)),
        ("haiku-4", ModelRate(input: 1.0, output: 5.0, cachedInput: 0.10, cacheWrite: 1.25)),
        ("haiku", ModelRate(input: 0.80, output: 4.0, cachedInput: 0.08, cacheWrite: 1.0)),
    ]

    private static let codexRates: [(String, ModelRate)] = [
        ("gpt-5", ModelRate(input: 1.25, output: 10.0, cachedInput: 0.125, cacheWrite: 0)),
        ("o3", ModelRate(input: 10.0, output: 40.0, cachedInput: 2.50, cacheWrite: 0)),
        ("o1", ModelRate(input: 15.0, output: 60.0, cachedInput: 7.50, cacheWrite: 0)),
        ("gpt-4o", ModelRate(input: 2.50, output: 10.0, cachedInput: 1.25, cacheWrite: 0)),
    ]

    static let defaultClaude = ModelRate(input: 3.0, output: 15.0, cachedInput: 0.30, cacheWrite: 3.75)
    static let defaultCodex = ModelRate(input: 1.25, output: 10.0, cachedInput: 0.125, cacheWrite: 0)

    static func rate(for model: String?, kind: ProviderKind) -> ModelRate {
        let table = kind == .claude ? claudeRates : codexRates
        let fallback = kind == .claude ? defaultClaude : defaultCodex

        guard let model = model?.lowercased(), !model.isEmpty else {
            return fallback
        }

        for (needle, rate) in table where model.contains(needle) {
            return rate
        }
        return fallback
    }

    static func cost(input: Int64, output: Int64, cachedRead: Int64, cacheWrite: Int64, rate: ModelRate) -> Double {
        let scale = 1_000_000.0
        return (Double(input) * rate.input
            + Double(output) * rate.output
            + Double(cachedRead) * rate.cachedInput
            + Double(cacheWrite) * rate.cacheWrite) / scale
    }
}

nonisolated func formatCost(_ value: Double) -> String {
    if value <= 0 {
        return "$0.00"
    }
    if value < 0.01 {
        return String(format: "$%.4f", value)
    }
    if value < 100 {
        return String(format: "$%.2f", value)
    }
    if value < 10_000 {
        return String(format: "$%.0f", value)
    }
    return String(format: "$%.1fK", value / 1_000)
}
