import Foundation
import SQLite3

private let sqliteDestructorTransient: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Parse export basenames → Photo library localIdentifiers (for reindexing disk)

enum BackupExportFilenameParser {
    /// Attempts to recover `PHAsset.localIdentifier` from a file basename (no path components).
    static func localIdentifier(fromExportBasename basename: String, naming: BackupFileNaming) -> String? {
        let name = basename as NSString
        let base = name.deletingPathExtension
        switch naming {
        case .localIdentifierOnly:
            return sanitizedIdToLocalIdentifier(base)
        case .datePrefixIdentifierOriginal:
            return fromDatePrefixed(base)
        case .identifierAndOriginal:
            return fromIdentifierAndOriginal(base)
        }
    }

    private static func fromDatePrefixed(_ base: String) -> String? {
        guard base.count >= 11 else { return nil }
        let idx = base.index(base.startIndex, offsetBy: 10)
        guard base[idx] == "_" else { return nil }
        let rest = String(base[base.index(after: idx)...])
        return fromIdentifierAndOriginal(rest)
    }

    /// `sanitizedId + "_" + safeOriginal` or legacy `sanitizedId + safeOriginal` (no underscore).
    private static func fromIdentifierAndOriginal(_ base: String) -> String? {
        let withUnderscore =
            #"^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(?:_L[0-9]+_[0-9]+)*)_(.+)$"#
        if let sanitized = matchGroup1(base, pattern: withUnderscore) {
            return sanitizedIdToLocalIdentifier(sanitized)
        }
        let legacyGlued =
            #"^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(?:_L[0-9]+_[0-9]+)*)(.+)$"#
        if let sanitized = matchGroup1(base, pattern: legacyGlued) {
            return sanitizedIdToLocalIdentifier(sanitized)
        }
        return nil
    }

    private static func matchGroup1(_ s: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = regex.firstMatch(in: s, options: [], range: range), m.numberOfRanges > 1 else { return nil }
        let r = m.range(at: 1)
        guard r.location != NSNotFound, let swiftRange = Range(r, in: s) else { return nil }
        return String(s[swiftRange])
    }

    private static func sanitizedIdToLocalIdentifier(_ sanitized: String) -> String {
        sanitized.replacingOccurrences(of: "_", with: "/")
    }
}

// MARK: - SQLite index

/// Tracks which library assets appear exported under the current backup folder + naming scheme.
final class BackupExportIndexStore: @unchecked Sendable {
    /// Single shared DB connection for the app (Shortcuts + UI share the same file).
    static let shared = BackupExportIndexStore()

    private let queue = DispatchQueue(label: "ArchiveAngel.exportIndex", qos: .utility)
    private var db: OpaquePointer?
    private let dbURL: URL

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        let dir: URL
        if let storageDirectory {
            dir = storageDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            dir = base.appendingPathComponent("ArchiveAngel", isDirectory: true)
        }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbURL = dir.appendingPathComponent("export_index.sqlite", isDirectory: false)
        queue.sync {
            openOrCreate()
        }
    }

    deinit {
        queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    private func openOrCreate() {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(dbURL.path, &handle, flags, nil) == SQLITE_OK, let h = handle else {
            db = nil
            return
        }
        db = h
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(
            db,
            """
            CREATE TABLE IF NOT EXISTS exported (
              local_id TEXT NOT NULL PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT NOT NULL PRIMARY KEY,
              value TEXT NOT NULL
            );
            """,
            nil,
            nil,
            nil
        )
    }

    private func fingerprint(forBookmarkData data: Data?) -> String {
        CryptoHelpers.sha256Hex(data ?? Data())
    }

    /// Whether the on-disk index matches this folder bookmark, layout, and naming.
    func isIndexValid(bookmarkData: Data?, layout: BackupFolderLayout, naming: BackupFileNaming) -> Bool {
        queue.sync {
            guard db != nil else { return false }
            let fp = fingerprint(forBookmarkData: bookmarkData)
            guard
                let sLayout = stringMeta("layout"),
                let sNaming = stringMeta("naming"),
                let sFp = stringMeta("bookmark_fp"),
                sLayout == layout.rawValue,
                sNaming == naming.rawValue,
                sFp == fp
            else {
                return false
            }
            return true
        }
    }

    private func stringMeta(_ key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        key.withCString { sqlite3_bind_text(stmt, 1, $0, -1, sqliteDestructorTransient) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                return String(cString: c)
            }
        }
        return nil
    }

    func setMeta(bookmarkData: Data?, layout: BackupFolderLayout, naming: BackupFileNaming) {
        queue.sync {
            guard let db else { return }
            let fp = fingerprint(forBookmarkData: bookmarkData)
            sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
            upsertMeta(key: "bookmark_fp", value: fp)
            upsertMeta(key: "layout", value: layout.rawValue)
            upsertMeta(key: "naming", value: naming.rawValue)
            upsertMeta(key: "schema", value: "1")
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    private func upsertMeta(key: String, value: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        key.withCString { sqlite3_bind_text(stmt, 1, $0, -1, sqliteDestructorTransient) }
        value.withCString { sqlite3_bind_text(stmt, 2, $0, -1, sqliteDestructorTransient) }
        _ = sqlite3_step(stmt)
    }

    /// Loads all exported ids into memory for fast missing counts.
    func allExportedLocalIdentifiers() -> Set<String> {
        queue.sync {
            var set = Set<String>()
            guard let db else { return set }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT local_id FROM exported", -1, &stmt, nil) == SQLITE_OK else {
                return set
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    set.insert(String(cString: c))
                }
            }
            return set
        }
    }

    func insertExportedAsset(localIdentifier: String) {
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(
                db,
                "INSERT OR IGNORE INTO exported(local_id) VALUES(?)",
                -1,
                &stmt,
                nil
            ) == SQLITE_OK else { return }
            localIdentifier.withCString { sqlite3_bind_text(stmt, 1, $0, -1, sqliteDestructorTransient) }
            _ = sqlite3_step(stmt)
        }
    }

    /// Clears exported rows and meta (e.g. folder cleared).
    func clearAll() {
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "DELETE FROM exported", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM meta", nil, nil, nil)
        }
    }

    /// Full folder scan; replaces `exported` contents. Caller must set meta after success. `onProgress` on this queue.
    func reindexBackupFolder(
        rootURL: URL,
        naming: BackupFileNaming,
        onProgress: ((_ filesVisited: Int) -> Void)? = nil
    ) throws {
        try queue.sync {
            guard let db else {
                throw BackupExportIndexError.databaseUnavailable
            }
            sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM exported", nil, nil, nil)

            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw BackupExportIndexError.enumeratorFailed
            }

            var visited = 0
            var insertStmt: OpaquePointer?
            defer { sqlite3_finalize(insertStmt) }
            let insertSQL = "INSERT OR IGNORE INTO exported(local_id) VALUES(?)"
            guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                throw BackupExportIndexError.databaseUnavailable
            }

            while let item = enumerator.nextObject() as? URL {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                let base = item.lastPathComponent
                if base == ".DS_Store" { continue }
                if let lid = BackupExportFilenameParser.localIdentifier(fromExportBasename: base, naming: naming) {
                    sqlite3_reset(insertStmt)
                    sqlite3_clear_bindings(insertStmt)
                    lid.withCString { sqlite3_bind_text(insertStmt, 1, $0, -1, sqliteDestructorTransient) }
                    _ = sqlite3_step(insertStmt)
                }
                visited += 1
                if visited % 2000 == 0 {
                    onProgress?(visited)
                }
            }

            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            onProgress?(visited)
        }
    }
}

enum BackupExportIndexError: Error {
    case databaseUnavailable
    case enumeratorFailed
}
