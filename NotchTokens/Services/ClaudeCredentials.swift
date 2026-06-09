//
//  ClaudeCredentials.swift
//  NotchTokens
//

import Foundation
import OSLog

nonisolated enum ClaudeCredentials {
    static func readAccessToken() -> String? {
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            return envToken
        }

        guard let raw = runSecurity(service: "Claude Code-credentials") else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return extractToken(from: object)
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractToken(from object: [String: Any]) -> String? {
        let candidates = ["accessToken", "access_token", "token"]
        for key in candidates {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }

        for value in object.values {
            if let nested = value as? [String: Any],
               let token = extractToken(from: nested) {
                return token
            }
        }
        return nil
    }

    private static func runSecurity(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            Log.credentials.debug("security spawn failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // Non-zero usually means the keychain item is missing or access was denied.
            Log.credentials.debug("security exited \(process.terminationStatus) for service \(service, privacy: .public)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        if output?.isEmpty ?? true {
            Log.credentials.debug("security returned empty output for service \(service, privacy: .public)")
        }
        return output
    }
}
