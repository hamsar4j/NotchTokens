//
//  PricingTableTests.swift
//  NotchTokensTests
//

import XCTest
@testable import NotchTokens

@MainActor
final class PricingTableTests: XCTestCase {

    private let sampleJSON = """
    {
      "claude-sonnet-4-5": {
        "input_cost_per_token": 0.000003,
        "output_cost_per_token": 0.000015,
        "cache_read_input_token_cost": 0.0000003,
        "cache_creation_input_token_cost": 0.00000375
      },
      "gpt-5": {
        "input_cost_per_token": 0.00000125,
        "output_cost_per_token": 0.00001
      }
    }
    """

    private func makeTable() throws -> PricingTable {
        try XCTUnwrap(PricingTable.decode(Data(sampleJSON.utf8)))
    }

    // MARK: - rate(for:) matching ladder

    func testExactMatch() throws {
        let table = try makeTable()
        let rate = try XCTUnwrap(table.rate(for: "claude-sonnet-4-5"))
        XCTAssertEqual(rate.input, 0.000003)
        XCTAssertEqual(rate.output, 0.000015)
    }

    func testMatchIsCaseInsensitive() throws {
        let table = try makeTable()
        XCTAssertNotNil(table.rate(for: "Claude-Sonnet-4-5"))
    }

    func testStripsDateSuffix() throws {
        let table = try makeTable()
        // 8-digit trailing date should be stripped before matching.
        let rate = try XCTUnwrap(table.rate(for: "claude-sonnet-4-5-20250929"))
        XCTAssertEqual(rate.input, 0.000003)
    }

    func testStripsVendorPrefix() throws {
        let table = try makeTable()
        let rate = try XCTUnwrap(table.rate(for: "openai/gpt-5"))
        XCTAssertEqual(rate.input, 0.00000125)
    }

    func testPrefixMatch() throws {
        let table = try makeTable()
        // Not exact, no date, no slash — falls through to the prefix loop.
        let rate = try XCTUnwrap(table.rate(for: "claude-sonnet-4-5-thinking"))
        XCTAssertEqual(rate.input, 0.000003)
    }

    func testUnknownModelReturnsNil() throws {
        let table = try makeTable()
        XCTAssertNil(table.rate(for: "totally-made-up-model"))
    }

    func testNilAndEmptyModelReturnNil() throws {
        let table = try makeTable()
        XCTAssertNil(table.rate(for: nil))
        XCTAssertNil(table.rate(for: ""))
    }

    // MARK: - decode

    func testDecodeRejectsInvalidJSON() {
        XCTAssertNil(PricingTable.decode(Data("not json".utf8)))
    }

    func testDecodeReturnsNilForEmptyTable() {
        // Entries missing the required cost fields are skipped; an all-skip table is nil.
        let json = #"{ "bad": { "foo": 1 } }"#
        XCTAssertNil(PricingTable.decode(Data(json.utf8)))
    }

    func testDecodeDefaultsCacheCostsWhenAbsent() throws {
        let table = try makeTable()
        let gpt = try XCTUnwrap(table.rate(for: "gpt-5"))
        // gpt-5 omits cache costs, so they default off input.
        XCTAssertEqual(gpt.cachedRead, gpt.input * 0.1, accuracy: 1e-12)
        XCTAssertEqual(gpt.cacheWrite, gpt.input * 1.25, accuracy: 1e-12)
    }
}
