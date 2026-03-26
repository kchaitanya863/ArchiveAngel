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

    private let store: AppStateStore
    private let backupManager = BackupManager()
    private let deduplicationManager = DeduplicationManager()

    init(store: AppStateStore = AppStateStore()) {
        self.store = store
        self.state = store.load()
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

    func resolvedBackupFolderURL() -> URL? {
        guard let data = state.backupFolderBookmark else { return nil }
        var stale = false
        // Security-scoped bookmarks from the document picker resolve with default options on iOS
        // (.withSecurityScope is macOS-only in Swift's URL API).
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        else {
            state.backupFolderBookmark = nil
            persist()
            folderBookmarkStaleNotice = "Could not open the saved backup folder. Please choose it again."
            return nil
        }
        if stale {
            state.backupFolderBookmark = nil
            persist()
            folderBookmarkStaleNotice = "The backup folder reference expired. Please select the folder again."
            return nil
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
                        self.alert = .init(title: "Backup canceled", message: "The backup was stopped before completion.")
                    } else {
                        self.alert = .init(
                            title: "Backup complete",
                            message:
                                "Files written this run: \(outcome.filesWritten). Items in folder: \(outcome.totalItemsInFolder)."
                        )
                    }
                    self.refreshMissingCounts()
                case .failure(let error):
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
                self.alert = .init(
                    title: "Folder cleared",
                    message: "Removed \(removed) item(s) from the backup folder."
                )
                self.refreshMissingCounts()
            case .failure(let error):
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
                            self.alert = .init(title: "No duplicates found", message: "No duplicate photos were detected.")
                        } else {
                            self.activeDialog = .deleteDuplicates
                        }
                    case .failure(let error):
                        if error is CancellationError {
                            self.alert = .init(title: "Scan canceled", message: "Duplicate scan was stopped.")
                        } else {
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
                    self.alert = .init(
                        title: "Duplicates removed",
                        message: "Removed \(count) duplicate photo(s). Videos are never changed."
                    )
                    self.refreshMediaCounts()
                case .failure(let error):
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
