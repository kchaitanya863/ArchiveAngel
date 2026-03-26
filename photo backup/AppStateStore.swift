import Foundation

/// Persists `AppPersistentState` to a JSON file under Application Support (or a custom directory for tests).
final class AppStateStore {
    private let fileURL: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.archiveangel.state", qos: .utility)

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        storageDirectory: URL? = nil
    ) {
        self.defaults = defaults
        let dir: URL
        if let storageDirectory = storageDirectory {
            dir = storageDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            dir = base.appendingPathComponent("ArchiveAngel", isDirectory: true)
        }
        self.fileURL = dir.appendingPathComponent("app_state.json", isDirectory: false)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load() -> AppPersistentState {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppPersistentState.self, from: data) {
            return decoded
        }
        return migrateFromUserDefaultsIfNeeded() ?? .default
    }

    func save(_ state: AppPersistentState) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(state) else { return }
            try? data.write(to: self.fileURL, options: [.atomic])
        }
    }

    /// One-time migration from legacy `UserDefaults` keys.
    private func migrateFromUserDefaultsIfNeeded() -> AppPersistentState? {
        let migratedKey = "ArchiveAngelMigratedUserDefaults_v1"
        guard !defaults.bool(forKey: migratedKey) else { return nil }

        var state = AppPersistentState.default
        state.totalBackupSize = Int64(defaults.integer(forKey: "totalBackupSize"))
        state.lastBackupDate = defaults.object(forKey: "lastBackupDate") as? Date

        defaults.set(true, forKey: migratedKey)
        defaults.removeObject(forKey: "totalBackupSize")
        defaults.removeObject(forKey: "lastBackupDate")

        save(state)
        return state
    }
}
