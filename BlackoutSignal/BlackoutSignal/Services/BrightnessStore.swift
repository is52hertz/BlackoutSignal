//
//  BrightnessStore.swift
//  BlackoutSignal
//
//  Durable record of the brightness values captured when entering blackout, so the
//  app can restore them even after a crash or force-quit. The file exists ONLY while
//  a blackout session is in progress: it is written on enter and deleted after a
//  clean restore. Therefore, finding it at launch means the previous session did not
//  exit cleanly — a cue to offer recovery.
//

import Foundation

/// A snapshot of the displays that were dimmed, keyed by stable display identity.
struct BlackoutSession: Codable, Equatable {
    /// stableKey (e.g. "vendor:model:serial") -> original brightness value to restore.
    var brightness: [String: Int]
    var enteredAt: Date

    init(brightness: [String: Int], enteredAt: Date = Date()) {
        self.brightness = brightness
        self.enteredAt = enteredAt
    }
}

/// Reads/writes the pending blackout session to disk. Plain file I/O, no UI.
final class BrightnessStore {
    let fileURL: URL

    /// - Parameter fileURL: override the storage location (used by tests). When nil,
    ///   defaults to Application Support/BlackoutSignal/session.json.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true))
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base
                .appendingPathComponent("BlackoutSignal", isDirectory: true)
                .appendingPathComponent("session.json", isDirectory: false)
        }
    }

    /// True when a session file is present (i.e. a previous run may not have restored).
    var hasPendingSession: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func save(_ session: BlackoutSession) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("BrightnessStore.save failed: \(error.localizedDescription)")
        }
    }

    func load() -> BlackoutSession? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BlackoutSession.self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
