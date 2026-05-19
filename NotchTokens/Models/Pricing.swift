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
    let inputAbove200k: Double?
    let outputAbove200k: Double?
    let cachedReadAbove200k: Double?
    let cacheWriteAbove200k: Double?
    let cacheWrite1h: Double?

    func cost(input: Int64, output: Int64, cachedRead: Int64, cacheWrite5m: Int64, cacheWrite1h: Int64) -> Double {
        let totalCacheWrite = cacheWrite5m + cacheWrite1h
        let contextSize = input + cachedRead + totalCacheWrite
        let useTier = contextSize > 200_000 && inputAbove200k != nil

        let i = useTier ? (inputAbove200k ?? self.input) : self.input
        let o = useTier ? (outputAbove200k ?? self.output) : self.output
        let cr = useTier ? (cachedReadAbove200k ?? self.cachedRead) : self.cachedRead
        let cw5m = useTier ? (cacheWriteAbove200k ?? self.cacheWrite) : self.cacheWrite
        let cw1h = self.cacheWrite1h ?? cw5m

        return Double(input) * i
            + Double(output) * o
            + Double(cachedRead) * cr
            + Double(cacheWrite5m) * cw5m
            + Double(cacheWrite1h) * cw1h
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
                cacheWrite: cacheWrite,
                inputAbove200k: entry["input_cost_per_token_above_200k_tokens"] as? Double,
                outputAbove200k: entry["output_cost_per_token_above_200k_tokens"] as? Double,
                cachedReadAbove200k: entry["cache_read_input_token_cost_above_200k_tokens"] as? Double,
                cacheWriteAbove200k: entry["cache_creation_input_token_cost_above_200k_tokens"] as? Double,
                cacheWrite1h: entry["cache_creation_input_token_cost_above_1hr"] as? Double
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
