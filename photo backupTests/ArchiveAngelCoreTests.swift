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
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppPersistentState.self, from: data)
        XCTAssertEqual(decoded.totalBackupSize, 42)
        XCTAssertEqual(decoded.includePhotos, false)
        XCTAssertEqual(decoded.lastBackupDate, state.lastBackupDate)
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
}
