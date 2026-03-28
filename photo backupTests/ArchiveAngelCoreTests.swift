import Photos
import XCTest
@testable import photo_backup

final class ArchiveAngelCoreTests: XCTestCase {

    func testBackupProgressEstimatedRemainingTime() {
        XCTAssertNil(BackupProgressMath.estimatedRemainingTime(elapsed: 1, processedSteps: 0, totalSteps: 10))
        XCTAssertNil(BackupProgressMath.estimatedRemainingTime(elapsed: 1, processedSteps: 10, totalSteps: 10))
        if let eta = BackupProgressMath.estimatedRemainingTime(elapsed: 10, processedSteps: 5, totalSteps: 10) {
            XCTAssertEqual(eta, 10, accuracy: 0.001)
        } else {
            XCTFail("Expected ETA")
        }
    }

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
        state.backupAlbumCollectionLocalIdentifiers = ["a", "b"]
        state.backupIncrementalEnabled = true
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppPersistentState.self, from: data)
        XCTAssertEqual(decoded.totalBackupSize, 42)
        XCTAssertEqual(decoded.includePhotos, false)
        XCTAssertEqual(decoded.lastBackupDate, state.lastBackupDate)
        XCTAssertEqual(decoded.backupFolderLayout, .byYearMonth)
        XCTAssertEqual(decoded.backupFileNaming, .datePrefixIdentifierOriginal)
        XCTAssertEqual(decoded.backupAlbumCollectionLocalIdentifiers, ["a", "b"])
        XCTAssertEqual(decoded.backupIncrementalEnabled, true)
    }

    func testAppPersistentStateDecodesMissingOutputKeys() throws {
        let json = """
        {"totalBackupSize":0,"includePhotos":true,"includeVideos":true,"includeLivePhotosAsVideo":true,"showThumbnail":true}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppPersistentState.self, from: data)
        XCTAssertEqual(decoded.backupFolderLayout, .flat)
        XCTAssertEqual(decoded.backupFileNaming, .identifierAndOriginal)
        XCTAssertEqual(decoded.backupAlbumCollectionLocalIdentifiers, [])
        XCTAssertEqual(decoded.backupIncrementalEnabled, false)
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

        let store = ActivityLogStore(storageDirectory: dir, maxEntries: 50)
        XCTAssertTrue(store.loadEntries().isEmpty)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0...50 {
            store.append(
                ActivityLogEntry(
                    date: base.addingTimeInterval(TimeInterval(i)),
                    kind: .folderChanged,
                    summary: "entry-\(i)"
                )
            )
        }

        let entries = store.loadEntries()
        XCTAssertEqual(entries.count, 50)
        XCTAssertTrue(entries.contains { $0.summary == "entry-50" })
        XCTAssertFalse(entries.contains { $0.summary == "entry-0" })

        store.clearAll()
        XCTAssertTrue(store.loadEntries().isEmpty)
    }

    func testDiskSpaceAssess() {
        XCTAssertEqual(BackupDiskSpaceEstimator.assess(freeBytes: nil, neededBytes: 100), .unknownFreeSpace)
        XCTAssertEqual(BackupDiskSpaceEstimator.assess(freeBytes: 500, neededBytes: 0), .sufficient)
        XCTAssertEqual(
            BackupDiskSpaceEstimator.assess(freeBytes: 500, neededBytes: 900),
            .insufficient(shortByBytes: 400)
        )

        let needed: Int64 = 200_000_000
        let free: Int64 = needed + 50_000_000
        if case .tightRemaining = BackupDiskSpaceEstimator.assess(freeBytes: free, neededBytes: needed) {
            // headroom 50MB is below minHeadroom (100MB)
        } else {
            XCTFail("Expected tightRemaining")
        }
    }

    func testFallbackEstimatedAssetBytesHeuristic() {
        let video = BackupDiskSpaceEstimator.fallbackEstimatedAssetBytes(
            mediaType: .video,
            pixelWidth: 0,
            pixelHeight: 0,
            durationSeconds: 2
        )
        XCTAssertGreaterThan(video, 5_000_000)

        let image = BackupDiskSpaceEstimator.fallbackEstimatedAssetBytes(
            mediaType: .image,
            pixelWidth: 2000,
            pixelHeight: 1500,
            durationSeconds: 0
        )
        XCTAssertGreaterThan(image, 100_000)
        XCTAssertLessThanOrEqual(image, 40_000_000)
    }

    func testBackupExportFilenameParserRoundTrip() {
        let id = "AAAAAAAB-AAAA-AAAA-AAAA-AAAAAAAAAAAA/L0/001"
        let sanitized = id.replacingOccurrences(of: "/", with: "_")
        let baseIO = sanitized + ".heic"
        XCTAssertEqual(
            BackupExportFilenameParser.localIdentifier(fromExportBasename: baseIO, naming: .localIdentifierOnly),
            id
        )
        let baseFull = sanitized + "_IMG_0001.JPG"
        XCTAssertEqual(
            BackupExportFilenameParser.localIdentifier(fromExportBasename: baseFull, naming: .identifierAndOriginal),
            id
        )
        let dated = "2024-01-15_" + sanitized + "_photo.jpg"
        XCTAssertEqual(
            BackupExportFilenameParser.localIdentifier(fromExportBasename: dated, naming: .datePrefixIdentifierOriginal),
            id
        )
    }

    func testLooseExportedFilenameMatching() {
        let id = "ABC123"
        XCTAssertTrue(
            BackupNaming.looseExportedFilename("ABC123_IMG_0001.jpg", matchesAssetId: id, naming: .identifierAndOriginal)
        )
        XCTAssertTrue(
            BackupNaming.looseExportedFilename("ABC123IMG.jpg", matchesAssetId: id, naming: .identifierAndOriginal)
        )
        XCTAssertFalse(
            BackupNaming.looseExportedFilename("AB_other.jpg", matchesAssetId: id, naming: .identifierAndOriginal)
        )
        XCTAssertTrue(
            BackupNaming.looseExportedFilename(
                "2024-06-01_ABC123_photo.jpg",
                matchesAssetId: id,
                naming: .datePrefixIdentifierOriginal
            )
        )
        XCTAssertTrue(
            BackupNaming.looseExportedFilename("ABC123.heic", matchesAssetId: id, naming: .localIdentifierOnly)
        )
    }

    func testBackupScopeRules() {
        let watermark = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(
            BackupScopeRules.isAssetNewOrChangedSinceLibraryWatermark(
                creationDate: Date(timeIntervalSince1970: 150),
                modificationDate: Date(timeIntervalSince1970: 150),
                watermark: watermark
            )
        )
        XCTAssertTrue(
            BackupScopeRules.isAssetNewOrChangedSinceLibraryWatermark(
                creationDate: Date(timeIntervalSince1970: 50),
                modificationDate: Date(timeIntervalSince1970: 150),
                watermark: watermark
            )
        )
        XCTAssertFalse(
            BackupScopeRules.isAssetNewOrChangedSinceLibraryWatermark(
                creationDate: Date(timeIntervalSince1970: 50),
                modificationDate: Date(timeIntervalSince1970: 90),
                watermark: watermark
            )
        )
        XCTAssertTrue(
            BackupScopeRules.shouldReexportExistingPrimaryFile(
                incrementalWatermark: watermark,
                fileExistsAtPrimaryExportPath: true,
                isBackedUpAtAnyKnownPath: true
            )
        )
        XCTAssertFalse(
            BackupScopeRules.shouldReexportExistingPrimaryFile(
                incrementalWatermark: nil,
                fileExistsAtPrimaryExportPath: true,
                isBackedUpAtAnyKnownPath: true
            )
        )
        XCTAssertTrue(BackupScopeRules.passesAlbumFilter(assetLocalIdentifier: "x", albumMemberIds: nil))
        XCTAssertTrue(BackupScopeRules.passesAlbumFilter(assetLocalIdentifier: "x", albumMemberIds: ["x", "y"]))
        XCTAssertFalse(BackupScopeRules.passesAlbumFilter(assetLocalIdentifier: "z", albumMemberIds: ["x"]))

        XCTAssertNil(BackupScope.effectiveIncrementalWatermark(isIncrementalEnabled: true, lastBackupDate: nil))
        XCTAssertNil(BackupScope.effectiveIncrementalWatermark(isIncrementalEnabled: false, lastBackupDate: Date()))
        XCTAssertNotNil(BackupScope.effectiveIncrementalWatermark(isIncrementalEnabled: true, lastBackupDate: Date()))
    }

    func testActivityLogKindFilterMatching() {
        XCTAssertTrue(ActivityLogKind.backupCompleted.matches(.backups))
        XCTAssertTrue(ActivityLogKind.shortcutBackupCompleted.matches(.backups))
        XCTAssertFalse(ActivityLogKind.folderChanged.matches(.backups))
        XCTAssertTrue(ActivityLogKind.folderChanged.matches(.folder))
        XCTAssertTrue(ActivityLogKind.dedupDeleted.matches(.duplicates))
        XCTAssertTrue(ActivityLogKind.backupFailed.matches(.issues))
        XCTAssertTrue(ActivityLogKind.backupCompleted.matches(.all))
    }

    func testActivityLogExportPlainText() {
        let e1 = ActivityLogEntry(
            date: Date(timeIntervalSince1970: 2_000),
            kind: .backupCompleted,
            summary: "Done",
            detail: "Wrote 3"
        )
        let e2 = ActivityLogEntry(
            date: Date(timeIntervalSince1970: 1_500),
            kind: .folderChanged,
            summary: "Folder set",
            detail: nil
        )
        let text = ActivityLogExport.plainTextDocument(entries: [e1, e2])
        XCTAssertTrue(text.contains("Done"))
        XCTAssertTrue(text.contains("Wrote 3"))
        XCTAssertTrue(text.contains("Folder set"))
        XCTAssertTrue(text.contains("backupCompleted"))
        XCTAssertTrue(text.contains("folderChanged"))
    }
}
