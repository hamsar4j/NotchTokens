//
//  ClaudeUsageService.swift
//  NotchTokens
//

import Foundation

nonisolated struct ClaudeLimitFetch {
    var limits: [LimitWindow]
    var statusMessage: String?
}

actor ClaudeUsageService {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private var failureCount = 0
    private var nextAllowedAttempt: Date?
    private var cachedLimits: [LimitWindow] = []
    private var lastLoggedStatus: String?

    func fetchLimits() async -> ClaudeLimitFetch {
        if let next = nextAllowedAttempt, next > Date() {
            return ClaudeLimitFetch(
                limits: cachedLimits,
                statusMessage: retryMessage("Claude limits retrying", nextAttempt: next)
            )
        }

        guard let token = ClaudeCredentials.readAccessToken() else {
            return recordFailure("Claude credentials unavailable", authProblem: true)
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("claude-cli/1.0 (external, notchtokens)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return recordFailure("Claude limits unavailable", authProblem: false)
            }
            guard (200..<300).contains(http.statusCode) else {
                return recordFailure(
                    "Claude limits HTTP \(http.statusCode)",
                    authProblem: http.statusCode == 401 || http.statusCode == 403
                )
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return recordFailure("Claude limits response was not JSON", authProblem: false)
            }
            let limits = Self.parseLimits(from: object)
            guard !limits.isEmpty else {
                return recordFailure("Claude limits response had no quota windows", authProblem: false)
            }
            recordSuccess()
            cachedLimits = limits
            logStatus("Claude limits \(Self.format(limits))")
            return ClaudeLimitFetch(limits: limits, statusMessage: nil)
        } catch {
            return recordFailure("Claude limits unavailable: \(error.localizedDescription)", authProblem: false)
        }
    }

    private func recordSuccess() {
        failureCount = 0
        nextAllowedAttempt = nil
    }

    private func recordFailure(_ message: String, authProblem: Bool) -> ClaudeLimitFetch {
        failureCount += 1
        let base: Double = authProblem ? 120 : 60
        let delay = min(600, base * pow(2.0, Double(failureCount - 1)))
        let next = Date().addingTimeInterval(delay)
        nextAllowedAttempt = next

        let status = retryMessage(message, nextAttempt: next)
        logStatus(status)
        return ClaudeLimitFetch(limits: cachedLimits, statusMessage: status)
    }

    private func retryMessage(_ message: String, nextAttempt: Date) -> String {
        let seconds = max(1, Int(nextAttempt.timeIntervalSinceNow.rounded(.up)))
        return "\(message); retry in \(seconds)s"
    }

    private func logStatus(_ message: String) {
        guard message != lastLoggedStatus else { return }
        lastLoggedStatus = message
        print("[Claude usage] \(message)")
    }

    static func parseLimits(from object: [String: Any]) -> [LimitWindow] {
        let root = (object["usage"] as? [String: Any]) ?? object

        let entries: [(label: String, candidates: [String])] = [
            ("5h", ["five_hour", "fiveHour", "five_hours"]),
            ("Week", ["seven_day", "sevenDay", "seven_days", "weekly"]),
            ("Extra", ["extra_usage", "extraUsage", "extra"]),
        ]

        var results: [LimitWindow] = []

        for entry in entries {
            for key in entry.candidates {
                if let raw = root[key] as? [String: Any], let limit = makeLimit(name: entry.label, from: raw) {
                    results.append(limit)
                    break
                }
            }
        }

        return results
    }

    private static func makeLimit(name: String, from raw: [String: Any]) -> LimitWindow? {
        let percentKeys = ["utilization", "used_percent", "usedPercent", "percent_used", "percentUsed"]
        var percent: Double?

        for key in percentKeys {
            if let value = raw[key] as? Double {
                percent = value
                break
            }
            if let value = raw[key] as? Int {
                percent = Double(value)
                break
            }
        }

        if percent == nil,
           let used = (raw["used"] as? Double) ?? (raw["used"] as? Int).map(Double.init),
           let limit = (raw["limit"] as? Double) ?? (raw["limit"] as? Int).map(Double.init),
           limit > 0 {
            percent = (used / limit) * 100
        }

        guard var value = percent else { return nil }
        if value <= 1.0 {
            value *= 100
        }
        value = min(max(value, 0), 100)

        let resetsAt: Date? = {
            if let iso = raw["resets_at"] as? String ?? raw["resetsAt"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: iso) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: iso)
            }
            if let epoch = raw["resets_at"] as? Double {
                return date(fromEpoch: epoch)
            }
            if let epoch = raw["resets_at"] as? Int {
                return date(fromEpoch: Double(epoch))
            }
            return nil
        }()

        return LimitWindow(name: name, usedPercent: value, resetsAt: resetsAt)
    }

    private static func date(fromEpoch epoch: Double) -> Date {
        let seconds = epoch > 10_000_000_000 ? epoch / 1000 : epoch
        return Date(timeIntervalSince1970: seconds)
    }

    private static func format(_ limits: [LimitWindow]) -> String {
        limits
            .map { "\($0.name)=\(Int($0.usedPercent.rounded()))%" }
            .joined(separator: " ")
    }
}
