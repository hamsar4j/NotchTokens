//
//  LocalUsageReaderTests.swift
//  NotchTokensTests
//

import XCTest
@testable import NotchTokens

@MainActor
final class LocalUsageReaderTests: XCTestCase {

    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotchTokensTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tempHome.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func provider(_ kind: ProviderKind, pricing: PricingTable = .empty) throws -> ProviderUsage {
        let reader = LocalUsageReader(pricing: pricing, baseDirectory: tempHome)
        return try XCTUnwrap(reader.readSnapshot().providers.first { $0.kind == kind })
    }

    private static func pricingTable() -> PricingTable {
        let json = """
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
        return PricingTable.decode(Data(json.utf8)) ?? .empty
    }

    private func claudeRecord(requestId: String, messageId: String, input: Int, output: Int) -> String {
        """
        {"requestId":"\(requestId)","timestamp":"2026-01-02T10:00:00Z","message":{"id":"\(messageId)","model":"claude-sonnet-4-5","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }

    // MARK: - Claude

    func testClaudeMissingDirReportsMissing() throws {
        // Nothing written -> no ~/.claude -> .missing, not .empty.
        XCTAssertEqual(try provider(.claude).state, .missing)
    }

    func testClaudeDedupesByRequestAndMessageId() throws {
        // Two identical request/message rows (a retry) must be counted once.
        let line = claudeRecord(requestId: "req1", messageId: "msg1", input: 100, output: 50)
        try write("\(line)\n\(line)\n", to: ".claude/projects/proj1/session.jsonl")

        XCTAssertEqual(try provider(.claude).totalTokens, 150)
    }

    func testClaudeDistinctMessagesBothCount() throws {
        let a = claudeRecord(requestId: "req1", messageId: "msg1", input: 100, output: 50)
        let b = claudeRecord(requestId: "req1", messageId: "msg2", input: 100, output: 50)
        try write("\(a)\n\(b)\n", to: ".claude/projects/proj1/session.jsonl")

        XCTAssertEqual(try provider(.claude).totalTokens, 300)
    }

    func testClaudeCostUsesPricingTable() throws {
        let line = claudeRecord(requestId: "req1", messageId: "msg1", input: 1000, output: 500)
        try write("\(line)\n", to: ".claude/projects/proj1/session.jsonl")

        let claude = try provider(.claude, pricing: Self.pricingTable())
        // 1000 * 3e-6 + 500 * 1.5e-5
        XCTAssertEqual(claude.cost, 0.0105, accuracy: 1e-9)
        XCTAssertEqual(claude.state, .ready)
    }

    func testClaudeSkipsMalformedLines() throws {
        let good = claudeRecord(requestId: "req1", messageId: "msg1", input: 100, output: 50)
        try write("not json\n\(good)\n{\"partial\":true}\n", to: ".claude/projects/proj1/session.jsonl")

        XCTAssertEqual(try provider(.claude).totalTokens, 150)
    }

    // MARK: - Codex

    func testCodexMissingDirReportsMissing() throws {
        XCTAssertEqual(try provider(.codex).state, .missing)
    }

    func testCodexUsesLastCumulativeTotalNotSum() throws {
        // token_count events carry a *cumulative* total; the last one wins (not a sum).
        let lines = """
        {"type":"session_meta","payload":{"model":"gpt-5"}}
        {"type":"event_msg","timestamp":"2026-01-02T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":700,"cached_input_tokens":0,"output_tokens":300,"total_tokens":1000}}}}
        {"type":"event_msg","timestamp":"2026-01-02T10:05:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":500,"total_tokens":1500}}}}
        """
        try write(lines + "\n", to: ".codex/sessions/2026/session.jsonl")

        XCTAssertEqual(try provider(.codex).totalTokens, 1500)
    }

    func testCodexSubtractsCachedInputBeforePricing() throws {
        // input_tokens (1000) includes cached (400); cost must charge 600 at input rate,
        // 400 at the cache-read rate, so cached tokens aren't double-charged at input price.
        let lines = """
        {"type":"session_meta","payload":{"model":"gpt-5"}}
        {"type":"event_msg","timestamp":"2026-01-02T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":200,"total_tokens":1200}}}}
        """
        try write(lines + "\n", to: ".codex/sessions/2026/session.jsonl")

        let codex = try provider(.codex, pricing: Self.pricingTable())
        // 600 * 1.25e-6 + 200 * 1e-5 + 400 * (1.25e-6 * 0.1)
        let expected = 600 * 1.25e-6 + 200 * 1e-5 + 400 * 1.25e-7
        XCTAssertEqual(codex.cost, expected, accuracy: 1e-12)
        XCTAssertEqual(codex.totalTokens, 1200)
    }

    func testCodexReadsRateLimits() throws {
        let lines = """
        {"type":"session_meta","payload":{"model":"gpt-5"}}
        {"type":"event_msg","timestamp":"2026-01-02T10:00:00Z","rate_limits":{"primary":{"used_percent":40},"secondary":{"used_percent":12}},"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"output_tokens":10,"total_tokens":20}}}}
        """
        try write(lines + "\n", to: ".codex/sessions/2026/session.jsonl")

        let limits = try provider(.codex).limits
        XCTAssertEqual(limits.first { $0.name == "Short" }?.usedPercent, 40)
        XCTAssertEqual(limits.first { $0.name == "Long" }?.usedPercent, 12)
    }

    // MARK: - OpenCode

    func testOpenCodeSumsPrecomputedCost() throws {
        let msg = """
        {"tokens":{"input":100,"output":50,"reasoning":10,"cache":{"read":5,"write":0}},"cost":0.0123,"time":{"created":1767348000000}}
        """
        try write(msg, to: ".local/share/opencode/storage/message/sess1/msg1.json")

        let oc = try provider(.opencode)
        XCTAssertEqual(oc.totalTokens, 165)   // 100 + 50 + 10 + 5 + 0
        XCTAssertEqual(oc.cost, 0.0123, accuracy: 1e-9)
        XCTAssertTrue(oc.limits.isEmpty)       // OpenCode has no rate-limit concept
    }
}
