//
//  ClaudeUsageService.swift
//  NotchTokens
//

import Foundation

nonisolated struct ClaudeUsageService {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetchLimits() async -> [LimitWindow] {
        guard let token = ClaudeCredentials.readAccessToken() else {
            return []
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("claude-cli/1.0 (external, notchtokens)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return []
            }
            return Self.parseLimits(from: object)
        } catch {
            return []
        }
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
                return Date(timeIntervalSince1970: epoch)
            }
            return nil
        }()

        return LimitWindow(name: name, usedPercent: value, resetsAt: resetsAt)
    }
}
