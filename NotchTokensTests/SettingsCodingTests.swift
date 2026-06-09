//
//  SettingsCodingTests.swift
//  NotchTokensTests
//

import XCTest
@testable import NotchTokens

@MainActor
final class SettingsCodingTests: XCTestCase {

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    func testEmptyObjectUsesDefaults() throws {
        let settings = try decode("{}")
        XCTAssertNil(settings.codexBudget)
        XCTAssertNil(settings.opencodeBudget)
        XCTAssertTrue(settings.showClaude)
        XCTAssertTrue(settings.showCodex)
        XCTAssertTrue(settings.showOpenCode)
    }

    func testMissingVisibilityFlagsDefaultToTrue() throws {
        // An old config that predates the show* flags should still show everything.
        let settings = try decode(#"{ "codexBudget": 50 }"#)
        XCTAssertEqual(settings.codexBudget, 50)
        XCTAssertTrue(settings.showClaude)
        XCTAssertTrue(settings.showCodex)
    }

    func testExtraUnknownKeysAreIgnored() throws {
        let settings = try decode(#"{ "showCodex": false, "futureFlag": 123, "nested": { "x": 1 } }"#)
        XCTAssertFalse(settings.showCodex)
        XCTAssertTrue(settings.showClaude)
    }

    func testRoundTripPreservesValues() throws {
        let original = Settings(
            codexBudget: 42.5,
            opencodeBudget: nil,
            showClaude: false,
            showCodex: true,
            showOpenCode: false
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(original, restored)
    }

    func testExplicitFalseFlagsDecode() throws {
        let settings = try decode(#"{ "showClaude": false, "showCodex": false, "showOpenCode": false }"#)
        XCTAssertFalse(settings.showClaude)
        XCTAssertFalse(settings.showCodex)
        XCTAssertFalse(settings.showOpenCode)
    }

    func testBudgetHelpersMapToKinds() {
        let settings = Settings(codexBudget: 30, opencodeBudget: 60)
        XCTAssertNil(settings.budget(for: .claude))
        XCTAssertEqual(settings.budget(for: .codex), 30)
        XCTAssertEqual(settings.budget(for: .opencode), 60)
    }
}
