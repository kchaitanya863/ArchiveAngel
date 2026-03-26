import Foundation

/// On-disk app preferences and backup metadata (JSON in Application Support).
struct AppPersistentState: Codable, Equatable {
    var totalBackupSize: Int64
    var lastBackupDate: Date?
    /// Security-scoped bookmark for the user-selected backup folder.
    var backupFolderBookmark: Data?
    var includePhotos: Bool
    var includeVideos: Bool
    var includeLivePhotosAsVideo: Bool
    var showThumbnail: Bool

    static let `default` = AppPersistentState(
        totalBackupSize: 0,
        lastBackupDate: nil,
        backupFolderBookmark: nil,
        includePhotos: true,
        includeVideos: true,
        includeLivePhotosAsVideo: true,
        showThumbnail: true
    )
}
