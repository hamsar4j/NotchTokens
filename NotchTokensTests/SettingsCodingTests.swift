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

    func testMissingAlertFieldsUseDefaults() throws {
        // A config written before alerts existed should default to the standard threshold,
        // with notifications on.
        let settings = try decode(#"{ "codexBudget": 50 }"#)
        XCTAssertEqual(settings.alertThreshold, Settings.defaultAlertThreshold)
        XCTAssertTrue(settings.notificationsEnabled)
    }

    func testAlertFieldsDecodeWhenPresent() throws {
        let settings = try decode(#"{ "alertThreshold": 90, "notificationsEnabled": false }"#)
        XCTAssertEqual(settings.alertThreshold, 90)
        XCTAssertFalse(settings.notificationsEnabled)
    }

    func testMissingDisplayModeDefaultsToAuto() throws {
        XCTAssertEqual(try decode("{}").displayMode, .auto)
    }

    func testDisplayModeDecodesWhenPresent() throws {
        XCTAssertEqual(try decode(#"{ "displayMode": "menuBar" }"#).displayMode, .menuBar)
    }

    func testMissingRefreshIntervalUsesDefault() throws {
        // A config written before the refresh-interval setting existed keeps the 60s cadence.
        XCTAssertEqual(try decode("{}").refreshInterval, Settings.defaultRefreshInterval)
    }

    func testRefreshIntervalDecodesWhenPresent() throws {
        XCTAssertEqual(try decode(#"{ "refreshInterval": 300 }"#).refreshInterval, 300)
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
