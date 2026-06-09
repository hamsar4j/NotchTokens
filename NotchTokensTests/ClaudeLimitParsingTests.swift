//
//  ClaudeLimitParsingTests.swift
//  NotchTokensTests
//

import XCTest
@testable import NotchTokens

@MainActor
final class ClaudeLimitParsingTests: XCTestCase {

    private func parse(_ json: String) throws -> [LimitWindow] {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        return ClaudeUsageService.parseLimits(from: object)
    }

    private func window(_ limits: [LimitWindow], named name: String) -> LimitWindow? {
        limits.first { $0.name == name }
    }

    func testUtilizationAsPercent() throws {
        let limits = try parse(#"{ "five_hour": { "utilization": 42 } }"#)
        let five = try XCTUnwrap(window(limits, named: "5h"))
        XCTAssertEqual(five.usedPercent, 42, accuracy: 1e-9)
    }

    func testFractionalUtilizationScaledToPercent() throws {
        // Values <= 1.0 are treated as fractions and scaled by 100.
        let limits = try parse(#"{ "five_hour": { "utilization": 0.25 } }"#)
        let five = try XCTUnwrap(window(limits, named: "5h"))
        XCTAssertEqual(five.usedPercent, 25, accuracy: 1e-9)
    }

    func testUsedOverLimitComputesPercent() throws {
        let limits = try parse(#"{ "seven_day": { "used": 30, "limit": 120 } }"#)
        let week = try XCTUnwrap(window(limits, named: "Week"))
        XCTAssertEqual(week.usedPercent, 25, accuracy: 1e-9)
    }

    func testPercentClampedTo100() throws {
        let limits = try parse(#"{ "five_hour": { "utilization": 250 } }"#)
        let five = try XCTUnwrap(window(limits, named: "5h"))
        XCTAssertEqual(five.usedPercent, 100, accuracy: 1e-9)
    }

    func testNestedUnderUsageKey() throws {
        let limits = try parse(#"{ "usage": { "five_hour": { "utilization": 10 } } }"#)
        XCTAssertNotNil(window(limits, named: "5h"))
    }

    func testCamelCaseKeysAccepted() throws {
        let limits = try parse(#"{ "fiveHour": { "usedPercent": 12 } }"#)
        XCTAssertNotNil(window(limits, named: "5h"))
    }

    func testResetsAtISO8601() throws {
        let limits = try parse(#"{ "five_hour": { "utilization": 10, "resets_at": "2026-06-09T12:00:00Z" } }"#)
        let five = try XCTUnwrap(window(limits, named: "5h"))
        XCTAssertNotNil(five.resetsAt)
    }

    func testResetsAtEpochSeconds() throws {
        let limits = try parse(#"{ "five_hour": { "utilization": 10, "resets_at": 1700000000 } }"#)
        let five = try XCTUnwrap(window(limits, named: "5h"))
        XCTAssertEqual(five.resetsAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testResetsAtEpochMillisecondsNormalized() throws {
        // Values beyond ~10^10 are assumed to be milliseconds and divided down.
        let limits = try parse(#"{ "five_hour": { "utilization": 10, "resets_at": 1700000000000 } }"#)
        let five = try XCTUnwrap(window(limits, named: "5h"))
        XCTAssertEqual(five.resetsAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testNoRecognizedWindowsYieldsEmpty() throws {
        XCTAssertTrue(try parse(#"{ "something_else": { "utilization": 10 } }"#).isEmpty)
    }

    func testWindowWithoutPercentSkipped() throws {
        XCTAssertTrue(try parse(#"{ "five_hour": { "foo": "bar" } }"#).isEmpty)
    }
}
