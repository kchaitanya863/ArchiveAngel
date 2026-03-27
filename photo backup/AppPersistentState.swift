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
    /// Subfolder structure under the backup root.
    var backupFolderLayout: BackupFolderLayout
    /// Filename pattern for exported assets.
    var backupFileNaming: BackupFileNaming

    static let `default` = AppPersistentState(
        totalBackupSize: 0,
        lastBackupDate: nil,
        backupFolderBookmark: nil,
        includePhotos: true,
        includeVideos: true,
        includeLivePhotosAsVideo: true,
        showThumbnail: true,
        backupFolderLayout: .flat,
        backupFileNaming: .identifierAndOriginal
    )

    enum CodingKeys: String, CodingKey {
        case totalBackupSize
        case lastBackupDate
        case backupFolderBookmark
        case includePhotos
        case includeVideos
        case includeLivePhotosAsVideo
        case showThumbnail
        case backupFolderLayout
        case backupFileNaming
    }

    init(
        totalBackupSize: Int64,
        lastBackupDate: Date?,
        backupFolderBookmark: Data?,
        includePhotos: Bool,
        includeVideos: Bool,
        includeLivePhotosAsVideo: Bool,
        showThumbnail: Bool,
        backupFolderLayout: BackupFolderLayout,
        backupFileNaming: BackupFileNaming
    ) {
        self.totalBackupSize = totalBackupSize
        self.lastBackupDate = lastBackupDate
        self.backupFolderBookmark = backupFolderBookmark
        self.includePhotos = includePhotos
        self.includeVideos = includeVideos
        self.includeLivePhotosAsVideo = includeLivePhotosAsVideo
        self.showThumbnail = showThumbnail
        self.backupFolderLayout = backupFolderLayout
        self.backupFileNaming = backupFileNaming
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBackupSize = try c.decodeIfPresent(Int64.self, forKey: .totalBackupSize) ?? 0
        lastBackupDate = try c.decodeIfPresent(Date.self, forKey: .lastBackupDate)
        backupFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .backupFolderBookmark)
        includePhotos = try c.decodeIfPresent(Bool.self, forKey: .includePhotos) ?? true
        includeVideos = try c.decodeIfPresent(Bool.self, forKey: .includeVideos) ?? true
        includeLivePhotosAsVideo = try c.decodeIfPresent(Bool.self, forKey: .includeLivePhotosAsVideo) ?? true
        showThumbnail = try c.decodeIfPresent(Bool.self, forKey: .showThumbnail) ?? true
        backupFolderLayout = try c.decodeIfPresent(BackupFolderLayout.self, forKey: .backupFolderLayout) ?? .flat
        backupFileNaming = try c.decodeIfPresent(BackupFileNaming.self, forKey: .backupFileNaming)
            ?? .identifierAndOriginal
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(totalBackupSize, forKey: .totalBackupSize)
        try c.encodeIfPresent(lastBackupDate, forKey: .lastBackupDate)
        try c.encodeIfPresent(backupFolderBookmark, forKey: .backupFolderBookmark)
        try c.encode(includePhotos, forKey: .includePhotos)
        try c.encode(includeVideos, forKey: .includeVideos)
        try c.encode(includeLivePhotosAsVideo, forKey: .includeLivePhotosAsVideo)
        try c.encode(showThumbnail, forKey: .showThumbnail)
        try c.encode(backupFolderLayout, forKey: .backupFolderLayout)
        try c.encode(backupFileNaming, forKey: .backupFileNaming)
    }
}
