import Foundation

private struct ActivityLogFile: Codable {
    var entries: [ActivityLogEntry]
}

/// Append-only activity log JSON next to app state (`activity_log.json`).
final class ActivityLogStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.archiveangel.activitylog", qos: .utility)
    private let maxEntries: Int

    init(
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil,
        maxEntries: Int = 400
    ) {
        self.maxEntries = max(50, maxEntries)
        let dir: URL
        if let storageDirectory = storageDirectory {
            dir = storageDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            dir = base.appendingPathComponent("ArchiveAngel", isDirectory: true)
        }
        self.fileURL = dir.appendingPathComponent("activity_log.json", isDirectory: false)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func loadEntries() -> [ActivityLogEntry] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let file = try? JSONDecoder().decode(ActivityLogFile.self, from: data)
            else {
                return []
            }
            return file.entries.sorted { $0.date > $1.date }
        }
    }

    func append(_ entry: ActivityLogEntry) {
        queue.sync {
            let stored: [ActivityLogEntry]
            if let data = try? Data(contentsOf: fileURL),
               let file = try? JSONDecoder().decode(ActivityLogFile.self, from: data) {
                stored = file.entries
            } else {
                stored = []
            }
            var merged = stored + [entry]
            merged.sort { $0.date > $1.date }
            if merged.count > maxEntries {
                merged = Array(merged.prefix(maxEntries))
            }
            let out = ActivityLogFile(entries: merged)
            guard let data = try? JSONEncoder().encode(out) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
        NotificationCenter.default.post(name: .archiveAngelActivityLogDidChange, object: nil)
    }

    func clearAll() {
        queue.sync {
            let empty = ActivityLogFile(entries: [])
            guard let data = try? JSONEncoder().encode(empty) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
        NotificationCenter.default.post(name: .archiveAngelActivityLogDidChange, object: nil)
    }
}
