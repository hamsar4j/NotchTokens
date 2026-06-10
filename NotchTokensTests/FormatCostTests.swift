//
//  FormatCostTests.swift
//  NotchTokensTests
//

import XCTest

@testable import NotchTokens

@MainActor
final class FormatCostTests: XCTestCase {

    func testZeroAndNegative() {
        XCTAssertEqual(formatCost(0), "$0.00")
        XCTAssertEqual(formatCost(-5), "$0.00")
    }

    func testSubCentUsesFourDecimals() {
        XCTAssertEqual(formatCost(0.0042), "$0.0042")
    }

    func testNormalRangeUsesTwoDecimals() {
        XCTAssertEqual(formatCost(12.5), "$12.50")
    }

    func testHundredsRoundToWhole() {
        XCTAssertEqual(formatCost(1234), "$1234")
    }

    func testThousandsUseKSuffix() {
        XCTAssertEqual(formatCost(12_500), "$12.5K")
    }
}
