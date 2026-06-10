//
//  LocalUsageReader.swift
//  NotchTokens
//

import Foundation

nonisolated struct LocalUsageReader {
    /// Days of per-day cost history collected for the sparkline, including today.
    static let historyDays = 14

    private static let rollingThirtyDayInterval: TimeInterval = 30 * 24 * 60 * 60
    /// Skip pathologically large session files — a single multi-GB JSONL would otherwise
    /// be materialized into a String and blow up memory. Real sessions are far smaller.
    private static let maxFileBytes = 50 * 1024 * 1024

    private let fileManager = FileManager.default
    private let calendar = Calendar.current
    private let pricing: PricingTable
    private let baseDirectory: URL

    init(pricing: PricingTable = .empty, baseDirectory: URL? = nil) {
        self.pricing = pricing
        self.baseDirectory = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func readSnapshot() -> UsageSnapshot {
        UsageSnapshot(providers: [readClaude(), readCodex(), readOpenCode()])
    }

    private func readClaude() -> ProviderUsage {
        let claudeRoot = home.appendingPathComponent(".claude", isDirectory: true)
        let projectsRoot = claudeRoot.appendingPathComponent("projects", isDirectory: true)

        guard fileManager.fileExists(atPath: claudeRoot.path) else {
            var placeholder = ProviderUsage.placeholder(kind: .claude, title: "Claude Code")
            placeholder.state = .missing
            return placeholder
        }

        var total: Int64 = 0
        var todayTotal: Int64 = 0
        var countedMessageIds = Set<String>()
        var lastActivity: Date?
        var cost: Double = 0
        var todayCost: Double = 0
        var yesterdayTotal: Int64 = 0
        var yesterdayCost: Double = 0
        var monthCost: Double = 0
        var modelAcc: [String: (tokens: Int64, cost: Double)] = [:]
        var dailyAcc: [Date: Double] = [:]

        for file in jsonlFiles(under: projectsRoot) {
            forEachJSONLine(in: file) { object in
                guard
                    let message = object["message"] as? [String: Any],
                    let usage = message["usage"] as? [String: Any]
                else {
                    return
                }

                let input = int64(usage["input_tokens"])
                let output = int64(usage["output_tokens"])
                let cacheRead = int64(usage["cache_read_input_tokens"])
                let cacheWriteTotal = int64(usage["cache_creation_input_tokens"])

                var cacheWrite1h: Int64 = 0
                var cacheWrite5m: Int64 = cacheWriteTotal
                if let breakdown = usage["cache_creation"] as? [String: Any] {
                    cacheWrite1h = int64(breakdown["ephemeral_1h_input_tokens"])
                    cacheWrite5m = int64(breakdown["ephemeral_5m_input_tokens"])
                    if cacheWrite1h + cacheWrite5m == 0 {
                        cacheWrite5m = cacheWriteTotal
                    }
                }

                let recordTotal = input + output + cacheRead + cacheWriteTotal

                guard recordTotal > 0 else { return }

                let messageId = (message["id"] as? String) ?? (object["uuid"] as? String)
                if let messageId {
                    let key = "\(object["requestId"] as? String ?? "request")-\(messageId)"
                    guard countedMessageIds.insert(key).inserted else { return }
                }

                total += recordTotal

                let modelName = (message["model"] as? String) ?? "<missing>"
                let rate = pricing.rate(for: modelName)
                let recordCost =
                    rate?.cost(
                        input: input,
                        output: output,
                        cachedRead: cacheRead,
                        cacheWrite5m: cacheWrite5m,
                        cacheWrite1h: cacheWrite1h
                    ) ?? 0
                cost += recordCost
                modelAcc[modelName, default: (0, 0)].tokens += recordTotal
                modelAcc[modelName, default: (0, 0)].cost += recordCost

                if let timestamp = parseDate(object["timestamp"] as? String) {
                    lastActivity = maxDate(lastActivity, timestamp)
                    if calendar.isDateInToday(timestamp) {
                        todayTotal += recordTotal
                        todayCost += recordCost
                    } else if isYesterdaySoFar(timestamp) {
                        yesterdayTotal += recordTotal
                        yesterdayCost += recordCost
                    }
                    if isInCurrentMonth(timestamp) {
                        monthCost += recordCost
                    }
                    if let day = historyDay(for: timestamp) {
                        dailyAcc[day, default: 0] += recordCost
                    }
                }
            }
        }

        if total == 0 {
            let fallback = readClaudeStatsCache(at: claudeRoot.appendingPathComponent("stats-cache.json"))
            total = fallback.total
            todayTotal = fallback.todayTotal
            lastActivity = fallback.lastActivity
        }

        return ProviderUsage(
            kind: .claude,
            title: "Claude Code",
            state: total > 0 ? .ready : .empty,
            totalTokens: total,
            todayTokens: todayTotal,
            lastActivity: lastActivity,
            limits: [],
            cost: cost,
            todayCost: todayCost,
            costWindowCost: monthCost,
            yesterdayCost: yesterdayCost,
            yesterdayTokens: yesterdayTotal,
            models: sortedModels(modelAcc),
            dailyCosts: sortedDailyCosts(dailyAcc)
        )
    }

    private func readCodex() -> ProviderUsage {
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)

        guard fileManager.fileExists(atPath: codexRoot.path) else {
            var placeholder = ProviderUsage.placeholder(kind: .codex, title: "Codex")
            placeholder.state = .missing
            return placeholder
        }

        let roots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true),
        ]

        let configuredModel = readCodexConfigModel(at: codexRoot.appendingPathComponent("config.toml"))

        var total: Int64 = 0
        var todayTotal: Int64 = 0
        var lastActivity: Date?
        var latestLimitTimestamp: Date?
        var latestLimits: [LimitWindow] = []
        var cost: Double = 0
        var todayCost: Double = 0
        var yesterdayTotal: Int64 = 0
        var yesterdayCost: Double = 0
        var rollingThirtyDayCost: Double = 0
        var modelAcc: [String: (tokens: Int64, cost: Double)] = [:]
        var dailyAcc: [Date: Double] = [:]

        for root in roots {
            for file in jsonlFiles(under: root) {
                var sessionTotal: Int64 = 0
                var sessionUsageRaw: [String: Any]?
                var sessionLastActivity: Date?
                var sessionModel: String?

                forEachJSONLine(in: file) { object in
                    if object["type"] as? String == "session_meta",
                        let payload = object["payload"] as? [String: Any]
                    {
                        sessionModel = sessionModel ?? (payload["model"] as? String)
                    }

                    guard
                        object["type"] as? String == "event_msg",
                        let payload = object["payload"] as? [String: Any],
                        payload["type"] as? String == "token_count"
                    else {
                        return
                    }

                    let timestamp = parseDate(object["timestamp"] as? String)

                    if let info = payload["info"] as? [String: Any],
                        let totalUsage = info["total_token_usage"] as? [String: Any]
                    {
                        let parsedTotal = codexTotal(from: totalUsage)
                        if parsedTotal > 0 {
                            sessionTotal = parsedTotal
                            sessionUsageRaw = totalUsage
                            if let timestamp {
                                sessionLastActivity = maxDate(sessionLastActivity, timestamp)
                            }
                        }
                        if sessionModel == nil {
                            sessionModel = info["model"] as? String
                        }
                    }

                    if let timestamp,
                        let rateLimits = object["rate_limits"] as? [String: Any],
                        latestLimitTimestamp == nil || timestamp > latestLimitTimestamp!
                    {
                        latestLimitTimestamp = timestamp
                        latestLimits = codexLimits(from: rateLimits)
                    }
                }

                guard sessionTotal > 0 else { continue }

                total += sessionTotal
                lastActivity = maxDate(lastActivity, sessionLastActivity)

                let rate = pricing.rate(for: sessionModel ?? configuredModel)
                let raw = sessionUsageRaw ?? [:]
                let inputRaw = int64(raw["input_tokens"])
                let cached = int64(raw["cached_input_tokens"])
                let sessionCost =
                    rate?.cost(
                        input: max(0, inputRaw - cached),
                        output: int64(raw["output_tokens"]),
                        cachedRead: cached,
                        cacheWrite5m: 0,
                        cacheWrite1h: 0
                    ) ?? 0
                cost += sessionCost
                let modelKey = sessionModel ?? configuredModel ?? "unknown"
                modelAcc[modelKey, default: (0, 0)].tokens += sessionTotal
                modelAcc[modelKey, default: (0, 0)].cost += sessionCost

                if let sessionLastActivity, calendar.isDateInToday(sessionLastActivity) {
                    todayTotal += sessionTotal
                    todayCost += sessionCost
                } else if let sessionLastActivity, isYesterdaySoFar(sessionLastActivity) {
                    yesterdayTotal += sessionTotal
                    yesterdayCost += sessionCost
                }
                if let sessionLastActivity, isInRollingThirtyDays(sessionLastActivity) {
                    rollingThirtyDayCost += sessionCost
                }
                // Sessions are attributed to their last-activity day, same as today/yesterday.
                if let sessionLastActivity, let day = historyDay(for: sessionLastActivity) {
                    dailyAcc[day, default: 0] += sessionCost
                }
            }
        }

        return ProviderUsage(
            kind: .codex,
            title: "Codex",
            state: total > 0 || !latestLimits.isEmpty ? .ready : .empty,
            totalTokens: total,
            todayTokens: todayTotal,
            lastActivity: lastActivity,
            limits: latestLimits,
            cost: cost,
            todayCost: todayCost,
            costWindowCost: rollingThirtyDayCost,
            costWindowLabel: "last 30d",
            yesterdayCost: yesterdayCost,
            yesterdayTokens: yesterdayTotal,
            models: sortedModels(modelAcc),
            dailyCosts: sortedDailyCosts(dailyAcc)
        )
    }

    private func readOpenCode() -> ProviderUsage {
        let messagesRoot =
            home
            .appendingPathComponent(".local/share/opencode/storage/message", isDirectory: true)

        guard fileManager.fileExists(atPath: messagesRoot.path) else {
            var placeholder = ProviderUsage.placeholder(kind: .opencode, title: "OpenCode")
            placeholder.state = .missing
            return placeholder
        }

        var total: Int64 = 0
        var todayTotal: Int64 = 0
        var cost: Double = 0
        var todayCost: Double = 0
        var yesterdayTotal: Int64 = 0
        var yesterdayCost: Double = 0
        var rollingThirtyDayCost: Double = 0
        var lastActivity: Date?
        var modelAcc: [String: (tokens: Int64, cost: Double)] = [:]
        var dailyAcc: [Date: Double] = [:]

        guard
            let enumerator = fileManager.enumerator(
                at: messagesRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return ProviderUsage.placeholder(kind: .opencode, title: "OpenCode")
        }

        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard
                let data = boundedData(at: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            guard let tokens = object["tokens"] as? [String: Any] else { continue }

            let input = int64(tokens["input"])
            let output = int64(tokens["output"])
            let reasoning = int64(tokens["reasoning"])
            var cacheRead: Int64 = 0
            var cacheWrite: Int64 = 0
            if let cache = tokens["cache"] as? [String: Any] {
                cacheRead = int64(cache["read"])
                cacheWrite = int64(cache["write"])
            }

            let messageTotal = input + output + reasoning + cacheRead + cacheWrite
            guard messageTotal > 0 else { continue }

            total += messageTotal

            let messageCost = double(object["cost"])
            cost += messageCost

            if let modelID = object["modelID"] as? String {
                let key = (object["providerID"] as? String).map { "\($0)/\(modelID)" } ?? modelID
                modelAcc[key, default: (0, 0)].tokens += messageTotal
                modelAcc[key, default: (0, 0)].cost += messageCost
            }

            let timestamp = parseOpenCodeTime(object["time"])
            if let timestamp {
                lastActivity = maxDate(lastActivity, timestamp)
                if calendar.isDateInToday(timestamp) {
                    todayTotal += messageTotal
                    todayCost += messageCost
                } else if isYesterdaySoFar(timestamp) {
                    yesterdayTotal += messageTotal
                    yesterdayCost += messageCost
                }
                if isInRollingThirtyDays(timestamp) {
                    rollingThirtyDayCost += messageCost
                }
                if let day = historyDay(for: timestamp) {
                    dailyAcc[day, default: 0] += messageCost
                }
            }
        }

        return ProviderUsage(
            kind: .opencode,
            title: "OpenCode",
            state: total > 0 ? .ready : .empty,
            totalTokens: total,
            todayTokens: todayTotal,
            lastActivity: lastActivity,
            limits: [],
            cost: cost,
            todayCost: todayCost,
            costWindowCost: rollingThirtyDayCost,
            costWindowLabel: "last 30d",
            yesterdayCost: yesterdayCost,
            yesterdayTokens: yesterdayTotal,
            models: sortedModels(modelAcc),
            dailyCosts: sortedDailyCosts(dailyAcc)
        )
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        let now = Date()
        return calendar.component(.year, from: date) == calendar.component(.year, from: now)
            && calendar.component(.month, from: date) == calendar.component(.month, from: now)
    }

    private func isInRollingThirtyDays(_ date: Date) -> Bool {
        let now = Date()
        let start = now.addingTimeInterval(-Self.rollingThirtyDayInterval)
        return date >= start && date <= now
    }

    /// Yesterday, but only up to the current time of day, so "today so far" compares
    /// against the same slice of yesterday rather than a full (larger) day.
    private func isYesterdaySoFar(_ date: Date) -> Bool {
        calendar.isDateInYesterday(date) && date <= Date().addingTimeInterval(-86_400)
    }

    /// Start-of-day bucket for the daily sparkline, or nil when the date falls outside the
    /// trailing `historyDays` window (future timestamps are dropped too).
    private func historyDay(for date: Date) -> Date? {
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        guard
            let windowStart = calendar.date(byAdding: .day, value: -(Self.historyDays - 1), to: today),
            day >= windowStart, day <= today
        else { return nil }
        return day
    }

    private func sortedDailyCosts(_ acc: [Date: Double]) -> [DailyCost] {
        acc
            .map { DailyCost(day: $0.key, cost: $0.value) }
            .sorted { $0.day < $1.day }
    }

    private func sortedModels(_ acc: [String: (tokens: Int64, cost: Double)]) -> [ModelUsage] {
        acc
            .map { ModelUsage(name: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.tokens > $1.tokens }
    }

    private func readCodexConfigModel(at file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }  // stop at first section header
            guard trimmed.hasPrefix("model"), trimmed.contains("=") else { continue }
            let value = trimmed.split(separator: "=", maxSplits: 1).last ?? ""
            let stripped =
                value
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return stripped.isEmpty ? nil : stripped
        }
        return nil
    }

    private func parseOpenCodeTime(_ value: Any?) -> Date? {
        guard let time = value as? [String: Any] else { return nil }
        let millis = double(time["created"])
        guard millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private var home: URL {
        baseDirectory
    }

    private func jsonlFiles(under root: URL) -> [URL] {
        guard
            fileManager.fileExists(atPath: root.path),
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }

        return
            files
            .sorted { $0.modified > $1.modified }
            .prefix(2_000)
            .map(\.url)
    }

    /// Memory-maps a file only if it's under `maxFileBytes`; returns nil otherwise.
    private func boundedData(at url: URL) -> Data? {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > Self.maxFileBytes
        {
            return nil
        }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func forEachJSONLine(in file: URL, _ body: ([String: Any]) -> Void) {
        guard
            let data = boundedData(at: file),
            let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        for line in text.split(whereSeparator: \.isNewline) {
            guard
                let lineData = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }
            body(object)
        }
    }

    private func readClaudeStatsCache(at file: URL) -> (total: Int64, todayTotal: Int64, lastActivity: Date?) {
        guard
            let data = try? Data(contentsOf: file),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (0, 0, nil)
        }

        var total: Int64 = 0
        if let modelUsage = object["modelUsage"] as? [String: Any] {
            for case let value as [String: Any] in modelUsage.values {
                total +=
                    int64(value["inputTokens"])
                    + int64(value["outputTokens"])
                    + int64(value["cacheReadInputTokens"])
                    + int64(value["cacheCreationInputTokens"])
            }
        }

        var todayTotal: Int64 = 0
        if let daily = object["dailyModelTokens"] as? [[String: Any]] {
            for item in daily {
                guard
                    let dateString = item["date"] as? String,
                    let date = parseDay(dateString),
                    calendar.isDateInToday(date),
                    let byModel = item["tokensByModel"] as? [String: Any]
                else {
                    continue
                }
                todayTotal += byModel.values.reduce(Int64(0)) { $0 + int64($1) }
            }
        }

        return (total, todayTotal, parseDay(object["lastComputedDate"] as? String))
    }

    private func codexTotal(from usage: [String: Any]) -> Int64 {
        let declared = int64(usage["total_tokens"])
        if declared > 0 { return declared }
        return int64(usage["input_tokens"]) + int64(usage["output_tokens"])
    }

    private func codexLimits(from rateLimits: [String: Any]) -> [LimitWindow] {
        ["primary", "secondary"].compactMap { key in
            guard let window = rateLimits[key] as? [String: Any] else { return nil }

            let resetSeconds = optionalDouble(window["resets_at"])
            return LimitWindow(
                name: key == "primary" ? "Short" : "Long",
                usedPercent: min(max(double(window["used_percent"]), 0), 100),
                resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private func parseDay(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.some(let l), .some(let r)): max(l, r)
        case (.some(let l), .none): l
        case (.none, .some(let r)): r
        case (.none, .none): nil
        }
    }

    private func int64(_ value: Any?) -> Int64 {
        switch value {
        case let v as Int: Int64(v)
        case let v as Int64: v
        case let v as Double: Int64(v)
        case let v as String: Int64(v) ?? 0
        default: 0
        }
    }

    private func double(_ value: Any?) -> Double {
        switch value {
        case let v as Double: v
        case let v as Int: Double(v)
        case let v as Int64: Double(v)
        case let v as String: Double(v) ?? 0
        default: 0
        }
    }

    private func optionalDouble(_ value: Any?) -> Double? {
        let parsed = double(value)
        return parsed > 0 ? parsed : nil
    }
}
