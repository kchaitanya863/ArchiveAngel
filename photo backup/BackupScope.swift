import Foundation
import Photos

/// User-facing album row for the scope picker (collection `localIdentifier` is stable).
struct PickableAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let kindLabel: String
}

/// Album list + membership helpers for scoped backup.
enum BackupAlbumCatalog {
    /// User albums and smart albums (excluding the main “library” smart album, which duplicates the whole library).
    static func loadPickableAlbums() -> [PickableAlbum] {
        var rows: [PickableAlbum] = []
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]

        let append: (PHAssetCollection, String) -> Void = { collection, kind in
            if PHAsset.fetchAssets(in: collection, options: nil).count == 0 { return }
            let raw = collection.localizedTitle ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.isEmpty ? "Untitled" : trimmed
            rows.append(PickableAlbum(id: collection.localIdentifier, title: title, kindLabel: kind))
        }

        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
            .enumerateObjects { collection, _, _ in
                append(collection, "Album")
            }

        PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: options)
            .enumerateObjects { collection, _, _ in
                if collection.assetCollectionSubtype == .smartAlbumUserLibrary { return }
                append(collection, "Smart album")
            }

        rows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return rows
    }

    /// Union of asset `localIdentifier`s contained in the given collections. Empty input is not used by callers for filtering.
    static func unionAssetLocalIdentifiers(collectionLocalIdentifiers: [String]) -> Set<String> {
        guard !collectionLocalIdentifiers.isEmpty else { return [] }
        var set = Set<String>()
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: collectionLocalIdentifiers,
            options: nil
        )
        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                set.insert(asset.localIdentifier)
            }
        }
        return set
    }
}

/// Pure rules for incremental backup and album filtering (testable without Photos).
enum BackupScopeRules {
    /// `watermark` is the end time of the last **successful** backup (`lastBackupDate`). When incremental mode is on,
    /// only items **added to the library or edited** strictly after that time are considered—**independent of the
    /// current backup folder**, so switching to a new drive does not re-copy your whole library.
    static func isAssetNewOrChangedSinceLibraryWatermark(
        creationDate: Date?,
        modificationDate: Date?,
        watermark: Date
    ) -> Bool {
        let created = creationDate ?? .distantPast
        let modified = modificationDate ?? created
        return created > watermark || modified > watermark
    }

    /// Replace existing files at the primary export path when incremental mode is on and this item already exists
    /// there (library metadata changed after the watermark).
    static func shouldReexportExistingPrimaryFile(
        incrementalWatermark: Date?,
        fileExistsAtPrimaryExportPath: Bool,
        isBackedUpAtAnyKnownPath: Bool
    ) -> Bool {
        guard incrementalWatermark != nil, fileExistsAtPrimaryExportPath, isBackedUpAtAnyKnownPath else {
            return false
        }
        return true
    }

    static func passesAlbumFilter(assetLocalIdentifier: String, albumMemberIds: Set<String>?) -> Bool {
        guard let members = albumMemberIds else { return true }
        return members.contains(assetLocalIdentifier)
    }
}

/// Shared eligibility checks for backup, missing counts, and disk estimates.
enum BackupScope {
    /// Active incremental watermark for this run, or `nil` when incremental is off or no prior successful backup.
    static func effectiveIncrementalWatermark(isIncrementalEnabled: Bool, lastBackupDate: Date?) -> Date? {
        guard isIncrementalEnabled, let last = lastBackupDate else { return nil }
        return last
    }

    static func albumMemberSet(collectionLocalIdentifiers: [String]) -> Set<String>? {
        if collectionLocalIdentifiers.isEmpty { return nil }
        return BackupAlbumCatalog.unionAssetLocalIdentifiers(collectionLocalIdentifiers: collectionLocalIdentifiers)
    }

    static func shouldVisitAsset(
        asset: PHAsset,
        includePhotos: Bool,
        includeVideos: Bool,
        albumMemberIds: Set<String>?,
        incrementalWatermark: Date?
    ) -> Bool {
        if asset.mediaType == .image && !includePhotos { return false }
        if asset.mediaType == .video && !includeVideos { return false }
        if !BackupScopeRules.passesAlbumFilter(
            assetLocalIdentifier: asset.localIdentifier,
            albumMemberIds: albumMemberIds
        ) {
            return false
        }
        guard let watermark = incrementalWatermark else { return true }
        return BackupScopeRules.isAssetNewOrChangedSinceLibraryWatermark(
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            watermark: watermark
        )
    }

    static func countEligibleAssets(
        includePhotos: Bool,
        includeVideos: Bool,
        albumCollectionLocalIdentifiers: [String],
        incrementalWatermark: Date?
    ) -> Int {
        let albumMembers = albumMemberSet(collectionLocalIdentifiers: albumCollectionLocalIdentifiers)
        if albumMembers?.isEmpty == true { return 0 }

        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var n = 0
        assets.enumerateObjects { asset, _, _ in
            if shouldVisitAsset(
                asset: asset,
                includePhotos: includePhotos,
                includeVideos: includeVideos,
                albumMemberIds: albumMembers,
                incrementalWatermark: incrementalWatermark
            ) {
                n += 1
            }
        }
        return n
    }
}
