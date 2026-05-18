//
//  SettingsStore.swift
//  NotchTokens
//

import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    private var cancellable: AnyCancellable?

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let loaded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = loaded
        } else {
            self.settings = .default
        }
    }

    private func save() {
        guard let dir = Self.fileURL.deletingLastPathComponent() as URL? else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private static var fileURL: URL {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
        return appSupport.appendingPathComponent("NotchTokens/config.json")
    }
}
