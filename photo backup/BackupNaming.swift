import Foundation
import Photos

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
    static func isAssetBackedUp(
        asset: PHAsset,
        directory: URL,
        layout: BackupFolderLayout,
        naming: BackupFileNaming
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
        return FileManager.default.fileExists(atPath: legacy.path)
    }

    static func preferredOriginalFilename(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        let ordered: [PHAssetResourceType] =
            asset.mediaType == .video
            ? [.video, .fullSizeVideo]
            : [.photo, .fullSizePhoto]

        for type in ordered {
            if let r = resources.first(where: { $0.type == type }) {
                let name = r.originalFilename
                if !name.isEmpty { return name }
            }
        }
        if let any = resources.first {
            let name = any.originalFilename
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
}
