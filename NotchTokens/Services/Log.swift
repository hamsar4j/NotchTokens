//
//  Log.swift
//  NotchTokens
//

import OSLog

/// Shared os.Logger instances. One subsystem, one category per concern, so logs are
/// filterable in Console.app or via:
///   log stream --predicate 'subsystem == "com.NotchTokens.NotchTokens"'
nonisolated enum Log {
    private static let subsystem = "com.NotchTokens.NotchTokens"

    static let pricing = Logger(subsystem: subsystem, category: "Pricing")
    static let claudeUsage = Logger(subsystem: subsystem, category: "ClaudeUsage")
    static let credentials = Logger(subsystem: subsystem, category: "Credentials")
}
