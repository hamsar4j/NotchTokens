//
//  Pricing.swift
//  NotchTokens
//

import Foundation

nonisolated struct ModelRate: Equatable {
    let input: Double
    let output: Double
    let cachedRead: Double
    let cacheWrite: Double

    func cost(input: Int64, output: Int64, cachedRead: Int64, cacheWrite: Int64) -> Double {
        Double(input) * self.input
            + Double(output) * self.output
            + Double(cachedRead) * self.cachedRead
            + Double(cacheWrite) * self.cacheWrite
    }
}

nonisolated struct PricingTable {
    let rates: [String: ModelRate]

    static let empty = PricingTable(rates: [:])

    func rate(for model: String?) -> ModelRate? {
        guard let model = model?.lowercased(), !model.isEmpty else { return nil }

        if let exact = rates[model] { return exact }

        if let trimmed = Self.stripDateSuffix(model), let rate = rates[trimmed] {
            return rate
        }

        if let prefixed = Self.stripVendorPrefix(model), let rate = rates[prefixed] {
            return rate
        }

        for (key, rate) in rates where model.hasPrefix(key) || key.hasPrefix(model) {
            return rate
        }

        return nil
    }

    private static func stripDateSuffix(_ model: String) -> String? {
        let parts = model.split(separator: "-")
        guard parts.count > 1, let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) else {
            return nil
        }
        return parts.dropLast().joined(separator: "-")
    }

    private static func stripVendorPrefix(_ model: String) -> String? {
        guard let slashIndex = model.firstIndex(of: "/") else { return nil }
        return String(model[model.index(after: slashIndex)...])
    }

    static func decode(_ data: Data) -> PricingTable? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var rates: [String: ModelRate] = [:]
        rates.reserveCapacity(object.count)

        for (key, value) in object {
            guard
                let entry = value as? [String: Any],
                let input = entry["input_cost_per_token"] as? Double,
                let output = entry["output_cost_per_token"] as? Double
            else {
                continue
            }

            let cachedRead = entry["cache_read_input_token_cost"] as? Double ?? input * 0.1
            let cacheWrite = entry["cache_creation_input_token_cost"] as? Double ?? input * 1.25

            rates[key.lowercased()] = ModelRate(
                input: input,
                output: output,
                cachedRead: cachedRead,
                cacheWrite: cacheWrite
            )
        }

        return rates.isEmpty ? nil : PricingTable(rates: rates)
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
