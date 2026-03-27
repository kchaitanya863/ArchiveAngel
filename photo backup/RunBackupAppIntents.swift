import AppIntents
import Foundation
import Photos

// MARK: - Photo access

@available(iOS 16.0, *)
private func ensurePhotoLibraryReadWriteAccess() async -> Bool {
    await withCheckedContinuation { continuation in
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited {
            continuation.resume(returning: true)
            return
        }
        if current == .denied || current == .restricted {
            continuation.resume(returning: false)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            continuation.resume(returning: status == .authorized || status == .limited)
        }
    }
}

// MARK: - Errors

@available(iOS 16.0, *)
enum RunBackupIntentError: LocalizedError {
    case photoAccessDenied

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            return "Archive Angel needs access to your photo library to run a backup."
        }
    }
}

// MARK: - Intent

/// Runs a full backup using the last selected folder and saved toggles (photos, videos, Live Photo export, thumbnails off for speed in automations).
@available(iOS 16.0, *)
struct RunBackupToLastFolderIntent: AppIntent {
    static var title: LocalizedStringResource = "Run backup to last folder"
    static var description = IntentDescription(
        "Exports new items from your photo library to the backup folder you last chose in Archive Angel. Uses the same include toggles and Live Photo option as in the app."
    )
    /// Brings the app to the foreground so the backup can run with fewer time limits and access is reliable.
    static var openAppWhenRun: Bool = true

    static var isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let activityLog = ActivityLogStore()

        guard await ensurePhotoLibraryReadWriteAccess() else {
            activityLog.append(
                ActivityLogEntry(
                    kind: .backupFailed,
                    summary: "Shortcuts backup blocked",
                    detail: "Photo library access was not granted."
                )
            )
            throw RunBackupIntentError.photoAccessDenied
        }

        let store = AppStateStore()
        var state = store.load()
        guard let folderURL = BackupBookmarkResolver.resolvedBackupFolderURL(state: &state, store: store) else {
            return .result(
                dialog: IntentDialog(
                    "No backup folder is saved. Open Archive Angel, tap “Choose backup folder,” then try this shortcut again."
                )
            )
        }

        let manager = BackupManager()
        let outcome: BackupOutcome
        do {
            outcome = try await withCheckedThrowingContinuation { continuation in
                manager.startBackup(
                    backupFolderURL: folderURL,
                    includePhotos: state.includePhotos,
                    includeVideos: state.includeVideos,
                    includeLivePhotosAsVideo: state.includeLivePhotosAsVideo,
                    showThumbnail: state.showThumbnail,
                    isCanceled: { false },
                    onProgress: { _, _, _ in },
                    onThumbnail: { _ in },
                    completion: { result in
                        switch result {
                        case .success(let value):
                            continuation.resume(returning: value)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                )
            }
        } catch {
            activityLog.append(
                ActivityLogEntry(
                    kind: .backupFailed,
                    summary: "Shortcuts backup failed",
                    detail: error.localizedDescription
                )
            )
            throw error
        }

        if outcome.canceled {
            activityLog.append(
                ActivityLogEntry(
                    kind: .backupCanceled,
                    summary: "Shortcuts backup did not finish",
                    detail: nil
                )
            )
            return .result(dialog: IntentDialog("Backup did not finish."))
        }

        state.totalBackupSize = outcome.totalSizeBytes
        state.lastBackupDate = Date()
        store.save(state)

        activityLog.append(
            ActivityLogEntry(
                kind: .shortcutBackupCompleted,
                summary: "Shortcuts backup finished",
                detail:
                    "Wrote \(outcome.filesWritten) file(s); \(outcome.totalItemsInFolder) item(s) in folder."
            )
        )

        NotificationCenter.default.post(name: .archiveAngelPersistentStateDidChange, object: nil)

        let message =
            "Wrote \(outcome.filesWritten) file(s) this run. The backup folder now has \(outcome.totalItemsInFolder) item(s)."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Shortcuts

@available(iOS 16.0, *)
struct ArchiveAngelAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunBackupToLastFolderIntent(),
            phrases: [
                "Run backup in \(.applicationName)",
                "Back up photos with \(.applicationName)",
                "Start \(.applicationName) backup",
            ],
            shortTitle: "Run backup",
            systemImageName: "square.and.arrow.down.on.square.fill"
        )
    }
}
