//
//  ModelRateCostTests.swift
//  NotchTokensTests
//

import XCTest
@testable import NotchTokens

@MainActor
final class ModelRateCostTests: XCTestCase {

    private func rate(
        input: Double = 2,
        output: Double = 10,
        cachedRead: Double = 1,
        cacheWrite: Double = 3,
        inputAbove200k: Double? = nil,
        outputAbove200k: Double? = nil,
        cachedReadAbove200k: Double? = nil,
        cacheWriteAbove200k: Double? = nil,
        cacheWrite1h: Double? = nil
    ) -> ModelRate {
        ModelRate(
            input: input,
            output: output,
            cachedRead: cachedRead,
            cacheWrite: cacheWrite,
            inputAbove200k: inputAbove200k,
            outputAbove200k: outputAbove200k,
            cachedReadAbove200k: cachedReadAbove200k,
            cacheWriteAbove200k: cacheWriteAbove200k,
            cacheWrite1h: cacheWrite1h
        )
    }

    func testBasicCost() {
        let cost = rate().cost(input: 100, output: 50, cachedRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        XCTAssertEqual(cost, 100 * 2 + 50 * 10, accuracy: 1e-9)
    }

    func testCacheCostsCounted() {
        let cost = rate().cost(input: 0, output: 0, cachedRead: 10, cacheWrite5m: 4, cacheWrite1h: 0)
        // cachedRead*1 + cacheWrite5m*3
        XCTAssertEqual(cost, 10 * 1 + 4 * 3, accuracy: 1e-9)
    }

    func test1hCacheFallsBackToWriteRateWhenUnspecified() {
        // cacheWrite1h is nil on the rate, so 1h writes are charged at the 5m write rate.
        let cost = rate().cost(input: 0, output: 0, cachedRead: 0, cacheWrite5m: 0, cacheWrite1h: 10)
        XCTAssertEqual(cost, 10 * 3, accuracy: 1e-9)
    }

    func test1hCacheUsesDedicatedRateWhenPresent() {
        let cost = rate(cacheWrite1h: 7).cost(input: 0, output: 0, cachedRead: 0, cacheWrite5m: 0, cacheWrite1h: 10)
        XCTAssertEqual(cost, 10 * 7, accuracy: 1e-9)
    }

    func testTierRatesApplyAbove200k() {
        let r = rate(inputAbove200k: 1)
        // 250k input -> context > 200k and a tier exists, so the cheaper tier rate applies.
        let cost = r.cost(input: 250_000, output: 0, cachedRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        XCTAssertEqual(cost, 250_000 * 1, accuracy: 1e-6)
    }

    func testBaseRatesBelow200k() {
        let r = rate(inputAbove200k: 1)
        let cost = r.cost(input: 100_000, output: 0, cachedRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        XCTAssertEqual(cost, 100_000 * 2, accuracy: 1e-6)
    }

    func testNoTierIgnoresLargeContext() {
        // No inputAbove200k -> base rates apply even past the 200k threshold.
        let cost = rate().cost(input: 250_000, output: 0, cachedRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        XCTAssertEqual(cost, 250_000 * 2, accuracy: 1e-6)
    }
}
