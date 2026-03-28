import Foundation
import Photos

/// Caches `contentsOfDirectory` per parent path so loose export matching stays fast on large libraries.
final class BackupParentDirectoryFilenameCache: @unchecked Sendable {
    private var storage: [String: Set<String>] = [:]

    func filenames(at parentDirectory: URL) -> Set<String> {
        let path = parentDirectory.path
        if let existing = storage[path] { return existing }
        guard FileManager.default.fileExists(atPath: path) else {
            storage[path] = []
            return []
        }
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        storage[path] = names
        return names
    }

    func invalidate(parentDirectory: URL) {
        storage.removeValue(forKey: parentDirectory.path)
    }
}

enum BackupNaming {
    /// Builds a stable, filesystem-safe backup URL using layout, naming style, and resource metadata.
    static func backupFileURL(
        directory: URL,
        asset: PHAsset,
        layout: BackupFolderLayout = .flat,
        naming: BackupFileNaming = .identifierAndOriginal
    ) -> URL {
        let original = preferredOriginalFilename(for: asset)
        let safeOriginal = sanitizeFilename(original)
        let idPart = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        let basename = BackupOutputPathMath.fileBasename(
            naming: naming,
            sanitizedId: idPart,
            sanitizedOriginalFilename: safeOriginal,
            creationDate: asset.creationDate
        )
        let subdirs = BackupOutputPathMath.folderComponents(
            layout: layout,
            creationDate: asset.creationDate,
            mediaType: asset.mediaType
        )
        var url = directory
        for part in subdirs {
            url = url.appendingPathComponent(part, isDirectory: false)
        }
        return url.appendingPathComponent(basename)
    }

    /// Older app builds concatenated local id + filename without a separator; used only to detect existing files.
    static func legacyBackupFileURL(directory: URL, asset: PHAsset) -> URL {
        let idPart = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        let name = idPart + sanitizeFilename(preferredOriginalFilename(for: asset))
        return directory.appendingPathComponent(name)
    }

    /// Whether a file for this asset already exists for the current layout/naming, or at a legacy flat path.
    /// When `matchOriginalFilenameLoosely` is true, also treats an export as present if any file in the **primary**
    /// export directory matches this asset’s stable id (same folder `backupFileURL` would use). That covers iCloud
    /// cases where `PHAssetResource.originalFilename` changes between runs so the exact basename differs.
    static func isAssetBackedUp(
        asset: PHAsset,
        directory: URL,
        layout: BackupFolderLayout,
        naming: BackupFileNaming,
        parentFilenameCache: BackupParentDirectoryFilenameCache? = nil,
        matchOriginalFilenameLoosely: Bool = false
    ) -> Bool {
        let primary = backupFileURL(directory: directory, asset: asset, layout: layout, naming: naming)
        if FileManager.default.fileExists(atPath: primary.path) { return true }

        let flatCurrentNaming = backupFileURL(directory: directory, asset: asset, layout: .flat, naming: naming)
        if flatCurrentNaming != primary, FileManager.default.fileExists(atPath: flatCurrentNaming.path) {
            return true
        }

        let flatDefault = backupFileURL(
            directory: directory,
            asset: asset,
            layout: .flat,
            naming: .identifierAndOriginal
        )
        if flatDefault != primary, flatDefault != flatCurrentNaming,
           FileManager.default.fileExists(atPath: flatDefault.path) {
            return true
        }

        let legacy = legacyBackupFileURL(directory: directory, asset: asset)
        if FileManager.default.fileExists(atPath: legacy.path) { return true }

        guard matchOriginalFilenameLoosely else { return false }

        let parent = primary.deletingLastPathComponent()
        let names: Set<String>
        if let cache = parentFilenameCache {
            names = cache.filenames(at: parent)
        } else {
            guard FileManager.default.fileExists(atPath: parent.path) else { return false }
            names = Set((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
        }
        let idPart = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        return names.contains(where: { looseExportedFilename($0, matchesAssetId: idPart, naming: naming) })
    }

    /// Removes prior exports that match this asset id in the primary export folder (same parent as `primaryExportURL`).
    /// Used when incremental mode must replace an export whose basename changed.
    static func removeLooseMatchingExportFiles(
        asset: PHAsset,
        primaryExportURL: URL,
        naming: BackupFileNaming,
        includeLivePhotosAsVideo: Bool,
        parentFilenameCache: BackupParentDirectoryFilenameCache
    ) {
        let parent = primaryExportURL.deletingLastPathComponent()
        let names = parentFilenameCache.filenames(at: parent)
        let idPart = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        for name in names where looseExportedFilename(name, matchesAssetId: idPart, naming: naming) {
            let url = parent.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            if includeLivePhotosAsVideo, asset.mediaSubtypes.contains(.photoLive), asset.mediaType == .image {
                let movURL = url.deletingPathExtension().appendingPathExtension("mov")
                try? FileManager.default.removeItem(at: movURL)
            }
        }
        parentFilenameCache.invalidate(parentDirectory: parent)
    }

    static func looseExportedFilename(_ filename: String, matchesAssetId idPart: String, naming: BackupFileNaming) -> Bool {
        switch naming {
        case .identifierAndOriginal:
            if filename.hasPrefix(idPart + "_") { return true }
            // Legacy flat export: `localId` + sanitized original (no `_` separator).
            if filename.hasPrefix(idPart), filename.count > idPart.count { return true }
            return false
        case .datePrefixIdentifierOriginal:
            return filename.contains("_" + idPart + "_")
        case .localIdentifierOnly:
            if filename == idPart { return true }
            if filename.hasPrefix(idPart + ".") { return true }
            return false
        }
    }

    static func preferredOriginalFilename(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        let ordered: [PHAssetResourceType] =
            asset.mediaType == .video
            ? [.video, .fullSizeVideo]
            : [.photo, .fullSizePhoto]

        for type in ordered {
            let ofType = resources.filter { $0.type == type }.sorted {
                $0.originalFilename.localizedStandardCompare($1.originalFilename) == .orderedAscending
            }
            for r in ofType {
                let name = r.originalFilename
                if !name.isEmpty { return name }
            }
        }
        let remainder = resources.sorted {
            $0.originalFilename.localizedStandardCompare($1.originalFilename) == .orderedAscending
        }
        for r in remainder {
            let name = r.originalFilename
            if !name.isEmpty { return name }
        }
        switch asset.mediaType {
        case .video:
            return "video.mov"
        case .image:
            return "image.jpg"
        default:
            return "asset"
        }
    }

    /// Removes path separators and trims unsafe characters for a single path component.
    static func sanitizeFilename(_ name: String) -> String {
        var s = name
        for ch in ["/", "\\", "\0"] {
            s = s.replacingOccurrences(of: ch, with: "_")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "file" }
        if s.hasPrefix(".") { s = "_" + s.dropFirst() }
        return String(s.prefix(200))
    }
}

enum BackupProgressMath {
    /// Progress in 0...100 for `processed` steps out of `total` (clamped).
    static func percent(processed: Int, total: Int) -> Double {
        guard total > 0 else { return 100 }
        let p = Double(processed) / Double(total) * 100
        return min(100, max(0, p))
    }

    /// Rough ETA from how fast we’re moving through in-scope items (includes skips).
    static func estimatedRemainingTime(elapsed: TimeInterval, processedSteps: Int, totalSteps: Int) -> TimeInterval? {
        guard totalSteps > 0, processedSteps > 0, processedSteps < totalSteps, elapsed > 0.05 else { return nil }
        let rate = Double(processedSteps) / elapsed
        guard rate > 0.001 else { return nil }
        return Double(totalSteps - processedSteps) / rate
    }

    static func formatThroughput(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func formatCompactDuration(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "—" }
        if t < 60 { return String(format: "%.0fs", t) }
        let m = Int(t) / 60
        let s = Int(t) % 60
        if m < 60 { return "\(m)m \(s)s" }
        let h = m / 60
        let m2 = m % 60
        return "\(h)h \(m2)m"
    }
}
