//
//  PricingFetcher.swift
//  NotchTokens
//

import Foundation

actor PricingFetcher {
    private static let remoteURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let cacheTTL: TimeInterval = 24 * 60 * 60

    private var table: PricingTable
    private var lastFetch: Date?

    init() {
        if let cached = Self.loadDiskCache(), let decoded = PricingTable.decode(cached.data) {
            self.table = decoded
            self.lastFetch = cached.modified
            return
        }

        if let bundled = Self.loadBundled(), let decoded = PricingTable.decode(bundled) {
            self.table = decoded
            return
        }

        self.table = .empty
    }

    func current() -> PricingTable {
        table
    }

    func refreshIfStale() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < Self.cacheTTL {
            return
        }

        var request = URLRequest(url: Self.remoteURL, timeoutInterval: 10)
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let decoded = PricingTable.decode(data)
            else {
                return
            }

            table = decoded
            lastFetch = Date()
            Self.saveDiskCache(data)
        } catch {
            // keep existing table on failure
        }
    }

    // MARK: - Disk cache

    private static var cacheURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }

        let appDir = dir.appendingPathComponent("NotchTokens", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("pricing.json")
    }

    private static func loadDiskCache() -> (data: Data, modified: Date)? {
        guard
            let url = cacheURL,
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
            let modified = values.contentModificationDate,
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return (data, modified)
    }

    private static func saveDiskCache(_ data: Data) {
        guard let url = cacheURL else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadBundled() -> Data? {
        guard let url = Bundle.main.url(forResource: "pricing-fallback", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
