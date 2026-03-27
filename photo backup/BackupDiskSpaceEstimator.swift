import Foundation
import Photos

/// Rough disk space math for items not yet in the backup folder and for destination volume capacity.
enum BackupDiskSpaceEstimator {

    enum Assessment: Equatable {
        case sufficient
        case tightRemaining(headroomBytes: Int64)
        case insufficient(shortByBytes: Int64)
        case unknownFreeSpace
    }

    /// Compares reported free space to an estimated byte requirement.
    static func assess(freeBytes: Int64?, neededBytes: Int64) -> Assessment {
        guard neededBytes > 0 else { return .sufficient }
        guard let free = freeBytes else { return .unknownFreeSpace }
        if free < neededBytes {
            return .insufficient(shortByBytes: neededBytes - free)
        }
        let headroom = free - neededBytes
        let trivialNeeded: Int64 = 10_000_000
        guard neededBytes >= trivialNeeded else { return .sufficient }
        let minHeadroom = max(neededBytes / 10, 100_000_000)
        if headroom < minHeadroom {
            return .tightRemaining(headroomBytes: headroom)
        }
        return .sufficient
    }

    /// Heuristic when Photos does not report resource sizes (e.g. iCloud-only placeholders).
    static func fallbackEstimatedAssetBytes(
        mediaType: PHAssetMediaType,
        pixelWidth: Int,
        pixelHeight: Int,
        durationSeconds: TimeInterval
    ) -> Int64 {
        switch mediaType {
        case .video:
            let sec = max(durationSeconds, 0.25)
            return Int64(sec * 3.5 * 1_000_000)
        case .image:
            let pixels = Int64(max(pixelWidth, 1)) * Int64(max(pixelHeight, 1))
            let bpp = 1.2
            let raw = Int64(Double(pixels) * bpp)
            return min(40_000_000, max(80_000, raw))
        case .audio, .unknown:
            return 1_000_000
        @unknown default:
            return 1_000_000
        }
    }

    static func estimatedExportBytes(for asset: PHAsset, includeLivePhotosAsVideo: Bool) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var imageResourceMax: Int64 = 0
        var videoResourceMax: Int64 = 0
        var pairedVideoSize: Int64 = 0

        for r in resources {
            let sz = r.aa_estimatedFileSizeBytes
            switch r.type {
            case .photo, .fullSizePhoto, .alternatePhoto, .photoProxy, .adjustmentBasePhoto:
                imageResourceMax = max(imageResourceMax, sz)
            case .video, .fullSizeVideo:
                videoResourceMax = max(videoResourceMax, sz)
            case .pairedVideo:
                pairedVideoSize = max(pairedVideoSize, sz)
            default:
                break
            }
        }

        let mainMax = asset.mediaType == .video ? videoResourceMax : imageResourceMax
        var total = mainMax
        let isLive = asset.mediaSubtypes.contains(.photoLive)
        if includeLivePhotosAsVideo && isLive {
            total += pairedVideoSize
            if pairedVideoSize == 0, mainMax > 0 {
                total += Int64(max(asset.duration, 0) * 2.0 * 1_000_000)
            }
        }

        if total == 0 {
            total = fallbackEstimatedAssetBytes(
                mediaType: asset.mediaType,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                durationSeconds: asset.duration
            )
            if includeLivePhotosAsVideo && isLive {
                total += Int64(max(asset.duration, 0) * 2.0 * 1_000_000)
            }
        }
        return total
    }

    /// Free bytes on the volume that contains this file or folder URL.
    static func volumeAvailableCapacityBytes(forContainingItemAt fileURL: URL) -> Int64? {
        var dir = fileURL
        if !dir.hasDirectoryPath {
            dir = dir.deletingLastPathComponent()
        }
        for _ in 0..<32 {
            if let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let cap = values.volumeAvailableCapacityForImportantUsage {
                return Int64(cap)
            }
            if let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
               let cap = values.volumeAvailableCapacity {
                return Int64(cap)
            }
            let parent = dir.deletingLastPathComponent()
            if parent.standardizedFileURL.path == dir.standardizedFileURL.path { break }
            dir = parent
        }
        return nil
    }
}

private extension PHAssetResource {
    var aa_estimatedFileSizeBytes: Int64 {
        if let n = value(forKey: "fileSize") as? NSNumber {
            return n.int64Value
        }
        return 0
    }
}
