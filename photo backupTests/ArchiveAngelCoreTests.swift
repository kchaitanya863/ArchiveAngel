import Photos
import XCTest
@testable import photo_backup

final class ArchiveAngelCoreTests: XCTestCase {

    func testBackupProgressMathPercent() {
        XCTAssertEqual(BackupProgressMath.percent(processed: 0, total: 10), 0, accuracy: 0.001)
        XCTAssertEqual(BackupProgressMath.percent(processed: 5, total: 10), 50, accuracy: 0.001)
        XCTAssertEqual(BackupProgressMath.percent(processed: 10, total: 10), 100, accuracy: 0.001)
        XCTAssertEqual(BackupProgressMath.percent(processed: 0, total: 0), 100, accuracy: 0.001)
        XCTAssertEqual(BackupProgressMath.percent(processed: 20, total: 10), 100, accuracy: 0.001)
    }

    func testSanitizeFilename() {
        XCTAssertEqual(BackupNaming.sanitizeFilename("hello.jpg"), "hello.jpg")
        XCTAssertEqual(BackupNaming.sanitizeFilename("a/b"), "a_b")
        XCTAssertEqual(BackupNaming.sanitizeFilename("   "), "file")
        XCTAssertTrue(BackupNaming.sanitizeFilename(".hidden").hasPrefix("_"))
    }

    func testSHA256KnownVector() {
        let data = Data("archive angel".utf8)
        let hex = CryptoHelpers.sha256Hex(data)
        XCTAssertEqual(
            hex,
            "9dbcfb7c1c41ceb2f25884657bf7b5a4206a94f17dd811da74116aa0eb9db41c"
        )
    }

    func testAppPersistentStateRoundTrip() throws {
        var state = AppPersistentState.default
        state.totalBackupSize = 42
        state.lastBackupDate = Date(timeIntervalSince1970: 1_700_000_000)
        state.includePhotos = false
        state.backupFolderLayout = .byYearMonth
        state.backupFileNaming = .datePrefixIdentifierOriginal
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppPersistentState.self, from: data)
        XCTAssertEqual(decoded.totalBackupSize, 42)
        XCTAssertEqual(decoded.includePhotos, false)
        XCTAssertEqual(decoded.lastBackupDate, state.lastBackupDate)
        XCTAssertEqual(decoded.backupFolderLayout, .byYearMonth)
        XCTAssertEqual(decoded.backupFileNaming, .datePrefixIdentifierOriginal)
    }

    func testAppPersistentStateDecodesMissingOutputKeys() throws {
        let json = """
        {"totalBackupSize":0,"includePhotos":true,"includeVideos":true,"includeLivePhotosAsVideo":true,"showThumbnail":true}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppPersistentState.self, from: data)
        XCTAssertEqual(decoded.backupFolderLayout, .flat)
        XCTAssertEqual(decoded.backupFileNaming, .identifierAndOriginal)
    }

    func testBackupOutputPathMathFolders() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 3
        comps.day = 15
        let date = cal.date(from: comps)!
        XCTAssertTrue(BackupOutputPathMath.folderComponents(layout: .flat, creationDate: date, mediaType: .image).isEmpty)
        XCTAssertEqual(
            BackupOutputPathMath.folderComponents(layout: .byYearMonth, creationDate: date, mediaType: .image),
            ["2024", "03"]
        )
        XCTAssertEqual(
            BackupOutputPathMath.folderComponents(layout: .byYearMonthDay, creationDate: date, mediaType: .image),
            ["2024", "03", "15"]
        )
        XCTAssertEqual(
            BackupOutputPathMath.folderComponents(layout: .byMediaType, creationDate: date, mediaType: .video),
            ["Videos"]
        )
        XCTAssertEqual(
            BackupOutputPathMath.folderComponents(layout: .byMediaTypeYearMonth, creationDate: date, mediaType: .image),
            ["Photos", "2024", "03"]
        )
    }

    func testBackupOutputPathMathBasenames() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 3
        comps.day = 8
        let d = cal.date(from: comps)!
        XCTAssertEqual(
            BackupOutputPathMath.fileBasename(
                naming: .identifierAndOriginal,
                sanitizedId: "id_x",
                sanitizedOriginalFilename: "IMG.heic",
                creationDate: d
            ),
            "id_x_IMG.heic"
        )
        XCTAssertEqual(
            BackupOutputPathMath.fileBasename(
                naming: .datePrefixIdentifierOriginal,
                sanitizedId: "id_x",
                sanitizedOriginalFilename: "IMG.heic",
                creationDate: d
            ),
            "2024-03-08_id_x_IMG.heic"
        )
        XCTAssertEqual(
            BackupOutputPathMath.fileBasename(
                naming: .localIdentifierOnly,
                sanitizedId: "id_x",
                sanitizedOriginalFilename: "IMG.heic",
                creationDate: nil
            ),
            "id_x.heic"
        )
    }

    func testAppStateStoreLoadSave() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let defaults = UserDefaults(suiteName: "ArchiveAngelCoreTests.\(UUID().uuidString)")!

        let store = AppStateStore(defaults: defaults, storageDirectory: dir)
        var state = AppPersistentState.default
        state.totalBackupSize = 99
        state.includeVideos = false
        store.save(state)

        let loaded = store.load()
        XCTAssertEqual(loaded.totalBackupSize, 99)
        XCTAssertEqual(loaded.includeVideos, false)
    }

    func testActivityLogEntryRoundTrip() throws {
        let entry = ActivityLogEntry(
            kind: .backupCompleted,
            summary: "Test",
            detail: "Detail line"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ActivityLogEntry.self, from: data)
        XCTAssertEqual(decoded.kind, .backupCompleted)
        XCTAssertEqual(decoded.summary, "Test")
        XCTAssertEqual(decoded.detail, "Detail line")
    }

    func testActivityLogStoreAppendTrimAndClear() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityLogStore(storageDirectory: dir, maxEntries: 3)
        XCTAssertTrue(store.loadEntries().isEmpty)

        store.append(ActivityLogEntry(kind: .folderChanged, summary: "One"))
        store.append(ActivityLogEntry(kind: .folderChanged, summary: "Two"))
        store.append(ActivityLogEntry(kind: .folderChanged, summary: "Three"))
        store.append(ActivityLogEntry(kind: .folderChanged, summary: "Four"))

        let entries = store.loadEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains { $0.summary == "Four" })
        XCTAssertFalse(entries.contains { $0.summary == "One" })

        store.clearAll()
        XCTAssertTrue(store.loadEntries().isEmpty)
    }
}
