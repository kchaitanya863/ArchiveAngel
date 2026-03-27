import Foundation
import Photos
import UIKit

enum ArchiveAngelDialog: String, Identifiable {
    case clearFolder
    case deleteDuplicates

    var id: String { rawValue }
}

@MainActor
final class ArchiveAngelViewModel: ObservableObject {

    @Published private(set) var state: AppPersistentState
    @Published var showDocumentPicker = false
    @Published var isBackupInProgress = false
    @Published var backupProgress: Double = 0
    @Published var progressMessage = ""
    @Published var currentThumbnail: UIImage?
    @Published var cancelBackupRequested = false

    @Published var isDedupScanInProgress = false
    @Published var dedupProgress: Double = 0
    @Published var dedupMessage = ""
    @Published var cancelDedupRequested = false
    @Published var scannedDuplicateLocalIds: [String] = []
    @Published var activeDialog: ArchiveAngelDialog?

    @Published var alert: ArchiveAngelAlert?
    @Published var folderBookmarkStaleNotice: String?

    @Published var totalPhotosCount = 0
    @Published var totalVideosCount = 0
    @Published var totalMissingPhotosCount = 0
    @Published var totalMissingVideosCount = 0

    @Published private(set) var activityLogEntries: [ActivityLogEntry] = []

    private let store: AppStateStore
    private let activityLogStore: ActivityLogStore
    private let backupManager = BackupManager()
    private let deduplicationManager = DeduplicationManager()
    private var persistentStateObserver: NSObjectProtocol?
    private var activityLogObserver: NSObjectProtocol?

    /// Backups that finished successfully (in-app or Shortcuts), derived from the log.
    var completedBackupLogCount: Int {
        activityLogEntries.filter {
            $0.kind == .backupCompleted || $0.kind == .shortcutBackupCompleted
        }.count
    }

    init(store: AppStateStore = AppStateStore(), activityLogStore: ActivityLogStore = ActivityLogStore()) {
        self.store = store
        self.activityLogStore = activityLogStore
        self.state = store.load()
        self.activityLogEntries = activityLogStore.loadEntries()
        persistentStateObserver = NotificationCenter.default.addObserver(
            forName: .archiveAngelPersistentStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadPersistentStateFromDisk()
            }
        }
        activityLogObserver = NotificationCenter.default.addObserver(
            forName: .archiveAngelActivityLogDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActivityLog()
            }
        }
    }

    deinit {
        if let persistentStateObserver {
            NotificationCenter.default.removeObserver(persistentStateObserver)
        }
        if let activityLogObserver {
            NotificationCenter.default.removeObserver(activityLogObserver)
        }
    }

    func refreshActivityLog() {
        activityLogEntries = activityLogStore.loadEntries()
    }

    func clearActivityLog() {
        activityLogStore.clearAll()
    }

    private func recordActivity(kind: ActivityLogKind, summary: String, detail: String? = nil) {
        activityLogStore.append(ActivityLogEntry(kind: kind, summary: summary, detail: detail))
    }

    private func reloadPersistentStateFromDisk() {
        state = store.load()
        refreshMediaCounts()
        refreshMissingCounts()
    }

    // MARK: - Persistence

    private func persist() {
        store.save(state)
    }

    func applySettingsFromUI(
        includePhotos: Bool,
        includeVideos: Bool,
        includeLivePhotosAsVideo: Bool,
        showThumbnail: Bool
    ) {
        state.includePhotos = includePhotos
        state.includeVideos = includeVideos
        state.includeLivePhotosAsVideo = includeLivePhotosAsVideo
        state.showThumbnail = showThumbnail
        persist()
    }

    // MARK: - Backup folder

    /// Resolves the saved folder URL. Mutations to `state` (e.g. clearing a stale bookmark) are applied asynchronously
    /// so this stays safe when called from SwiftUI view bodies (e.g. via `backupFolderDisplayName`).
    func resolvedBackupFolderURL() -> URL? {
        var working = state
        let hadBookmark = working.backupFolderBookmark != nil
        guard let url = BackupBookmarkResolver.resolvedBackupFolderURL(state: &working, store: store) else {
            if working != state {
                let showStaleNotice = hadBookmark && working.backupFolderBookmark == nil
                Task { @MainActor in
                    self.state = working
                    if showStaleNotice {
                        self.folderBookmarkStaleNotice =
                            "The backup folder could not be opened or its reference expired. Please select the folder again."
                    }
                    self.refreshMissingCounts()
                }
            }
            return nil
        }
        if working != state {
            Task { @MainActor in self.state = working }
        }
        return url
    }

    func dismissBookmarkNotice() {
        folderBookmarkStaleNotice = nil
    }

    func userPickedBackupFolder(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            state.backupFolderBookmark = data
            persist()
            url.stopAccessingSecurityScopedResource()
            folderBookmarkStaleNotice = nil
            refreshMissingCounts()
            recordActivity(
                kind: .folderChanged,
                summary: "Backup folder set to “\(url.lastPathComponent)”",
                detail: nil
            )
        } catch {
            alert = .init(title: "Folder error", message: error.localizedDescription)
        }
    }

    var backupFolderDisplayName: String? {
        resolvedBackupFolderURL()?.lastPathComponent
    }

    // MARK: - Library stats

    func refreshMediaCounts() {
        let photosOptions = PHFetchOptions()
        photosOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        totalPhotosCount = PHAsset.fetchAssets(with: photosOptions).count

        let videosOptions = PHFetchOptions()
        videosOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        totalVideosCount = PHAsset.fetchAssets(with: videosOptions).count
    }

    func refreshMissingCounts() {
        guard let url = resolvedBackupFolderURL() else {
            totalMissingPhotosCount = 0
            totalMissingVideosCount = 0
            return
        }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        var missingPhotos = 0
        var missingVideos = 0
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        assets.enumerateObjects { [self] asset, _, _ in
            if asset.mediaType == .image && !self.state.includePhotos { return }
            if asset.mediaType == .video && !self.state.includeVideos { return }
            if BackupNaming.isAssetBackedUp(asset: asset, directory: url) { return }
            if asset.mediaType == .image { missingPhotos += 1 }
            else if asset.mediaType == .video { missingVideos += 1 }
        }
        totalMissingPhotosCount = missingPhotos
        totalMissingVideosCount = missingVideos
    }

    // MARK: - Backup

    func startBackup() {
        guard let folderURL = resolvedBackupFolderURL() else {
            alert = .init(title: "No folder selected", message: "Please select a folder to back up your photos.")
            return
        }

        isBackupInProgress = true
        backupProgress = 0
        cancelBackupRequested = false
        progressMessage = ""

        backupManager.startBackup(
            backupFolderURL: folderURL,
            includePhotos: state.includePhotos,
            includeVideos: state.includeVideos,
            includeLivePhotosAsVideo: state.includeLivePhotosAsVideo,
            showThumbnail: state.showThumbnail,
            isCanceled: { [weak self] in
                self?.cancelBackupRequested ?? false
            },
            onProgress: { [weak self] processed, total, message in
                guard let self = self else { return }
                self.backupProgress = BackupProgressMath.percent(processed: processed, total: total)
                self.progressMessage = message
            },
            onThumbnail: { [weak self] image in
                self?.currentThumbnail = image
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.isBackupInProgress = false
                self.cancelBackupRequested = false
                switch result {
                case .success(let outcome):
                    self.state.totalBackupSize = outcome.totalSizeBytes
                    self.state.lastBackupDate = Date()
                    self.persist()
                    if outcome.canceled {
                        self.recordActivity(
                            kind: .backupCanceled,
                            summary: "Backup canceled",
                            detail: "Stopped before completion."
                        )
                        self.alert = .init(title: "Backup canceled", message: "The backup was stopped before completion.")
                    } else {
                        self.recordActivity(
                            kind: .backupCompleted,
                            summary: "Backup finished",
                            detail:
                                "Wrote \(outcome.filesWritten) file(s); \(outcome.totalItemsInFolder) item(s) in folder."
                        )
                        self.alert = .init(
                            title: "Backup complete",
                            message:
                                "Files written this run: \(outcome.filesWritten). Items in folder: \(outcome.totalItemsInFolder)."
                        )
                    }
                    self.refreshMissingCounts()
                case .failure(let error):
                    self.recordActivity(
                        kind: .backupFailed,
                        summary: "Backup failed",
                        detail: error.localizedDescription
                    )
                    self.alert = .init(title: "Backup failed", message: error.localizedDescription)
                }
            }
        )
    }

    func cancelBackup() {
        cancelBackupRequested = true
    }

    // MARK: - Clear folder

    func requestClearFolder() {
        guard resolvedBackupFolderURL() != nil else {
            alert = .init(title: "No folder selected", message: "Choose a backup folder first.")
            return
        }
        activeDialog = .clearFolder
    }

    func performClearFolder() {
        activeDialog = nil
        guard let folderURL = resolvedBackupFolderURL() else { return }
        backupManager.clearFolderContents(backupFolderURL: folderURL) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let removed):
                self.state.totalBackupSize = 0
                self.persist()
                self.recordActivity(
                    kind: .folderCleared,
                    summary: "Cleared backup folder",
                    detail: "Removed \(removed) item(s)."
                )
                self.alert = .init(
                    title: "Folder cleared",
                    message: "Removed \(removed) item(s) from the backup folder."
                )
                self.refreshMissingCounts()
            case .failure(let error):
                self.recordActivity(
                    kind: .folderClearFailed,
                    summary: "Could not clear folder",
                    detail: error.localizedDescription
                )
                self.alert = .init(title: "Could not clear folder", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Deduplication (photos only)

    func startDuplicateScan() {
        isDedupScanInProgress = true
        dedupProgress = 0
        dedupMessage = ""
        cancelDedupRequested = false
        scannedDuplicateLocalIds = []

        deduplicationManager.scanDuplicatePhotos(
            isCanceled: { [weak self] in
                self?.cancelDedupRequested ?? false
            },
            onProgress: { [weak self] processed, total, message in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.dedupProgress = BackupProgressMath.percent(processed: processed, total: total) / 100
                    self.dedupMessage = message
                }
            },
            completion: { [weak self] result in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isDedupScanInProgress = false
                    self.cancelDedupRequested = false
                    switch result {
                    case .success(let ids):
                        self.scannedDuplicateLocalIds = ids
                        if ids.isEmpty {
                            self.recordActivity(
                                kind: .dedupNoDuplicates,
                                summary: "Duplicate scan: none found",
                                detail: nil
                            )
                            self.alert = .init(title: "No duplicates found", message: "No duplicate photos were detected.")
                        } else {
                            self.recordActivity(
                                kind: .dedupDuplicatesFound,
                                summary: "Found \(ids.count) duplicate photo(s)",
                                detail: "Awaiting confirmation to remove from library."
                            )
                            self.activeDialog = .deleteDuplicates
                        }
                    case .failure(let error):
                        if error is CancellationError {
                            self.recordActivity(
                                kind: .dedupScanCanceled,
                                summary: "Duplicate scan canceled",
                                detail: nil
                            )
                            self.alert = .init(title: "Scan canceled", message: "Duplicate scan was stopped.")
                        } else {
                            self.recordActivity(
                                kind: .dedupScanFailed,
                                summary: "Duplicate scan failed",
                                detail: error.localizedDescription
                            )
                            self.alert = .init(title: "Scan failed", message: error.localizedDescription)
                        }
                    }
                }
            }
        )
    }

    func cancelDedupScan() {
        cancelDedupRequested = true
    }

    func confirmDeleteScannedDuplicates() {
        activeDialog = nil
        let ids = scannedDuplicateLocalIds
        guard !ids.isEmpty else { return }

        isDedupScanInProgress = true
        dedupMessage = "Deleting duplicates…"
        dedupProgress = 0

        deduplicationManager.deleteAssets(localIdentifiers: ids) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.isDedupScanInProgress = false
                self.scannedDuplicateLocalIds = []
                self.dedupMessage = ""
                switch result {
                case .success(let count):
                    self.recordActivity(
                        kind: .dedupDeleted,
                        summary: "Removed \(count) duplicate photo(s)",
                        detail: "Videos were not changed."
                    )
                    self.alert = .init(
                        title: "Duplicates removed",
                        message: "Removed \(count) duplicate photo(s). Videos are never changed."
                    )
                    self.refreshMediaCounts()
                case .failure(let error):
                    self.recordActivity(
                        kind: .dedupDeleteFailed,
                        summary: "Deleting duplicates failed",
                        detail: error.localizedDescription
                    )
                    self.alert = .init(title: "Delete failed", message: error.localizedDescription)
                }
            }
        }
    }

    func cancelDuplicateDeletionDialog() {
        activeDialog = nil
        scannedDuplicateLocalIds = []
    }
}

struct ArchiveAngelAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
