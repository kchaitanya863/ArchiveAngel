import AVFoundation
import Photos
import UIKit

struct BackupOutcome {
    let filesWritten: Int
    let canceled: Bool
    let totalSizeBytes: Int64
    let totalItemsInFolder: Int
}

enum BackupManagerError: Error {
    case securityScopeDenied
}

extension BackupManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .securityScopeDenied:
            return "Could not access the backup folder. Open Archive Angel and select the folder again."
        }
    }
}

final class BackupManager {

    /// Counts library assets that would be considered for backup given include flags.
    static func countEligibleAssets(includePhotos: Bool, includeVideos: Bool) -> Int {
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var n = 0
        assets.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image && includePhotos { n += 1 }
            else if asset.mediaType == .video && includeVideos { n += 1 }
        }
        return n
    }

    func startBackup(
        backupFolderURL: URL,
        includePhotos: Bool,
        includeVideos: Bool,
        includeLivePhotosAsVideo: Bool,
        showThumbnail: Bool,
        isCanceled: @escaping () -> Bool,
        onProgress: @escaping (_ processed: Int, _ total: Int, _ message: String) -> Void,
        onThumbnail: @escaping (UIImage?) -> Void,
        completion: @escaping (Result<BackupOutcome, Error>) -> Void
    ) {
        guard backupFolderURL.startAccessingSecurityScopedResource() else {
            completion(.failure(BackupManagerError.securityScopeDenied))
            return
        }

        let totalWork = Self.countEligibleAssets(includePhotos: includePhotos, includeVideos: includeVideos)
        var processed = 0
        var filesWritten = 0
        var currentTotalSize: Int64 = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            let imageManager = PHImageManager.default()

            assets.enumerateObjects { asset, _, stop in
                if isCanceled() {
                    stop.pointee = true
                    return
                }

                if asset.mediaType == .image && !includePhotos { return }
                if asset.mediaType == .video && !includeVideos { return }

                processed += 1
                let fileURL = BackupNaming.backupFileURL(directory: backupFolderURL, asset: asset)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let size = attributes[.size] as? Int64 {
                        currentTotalSize += size
                    }
                    DispatchQueue.main.async {
                        onProgress(processed, totalWork, "Skipped (exists) \(processed) of \(totalWork)…")
                    }
                    return
                }

                if showThumbnail {
                    let options = PHImageRequestOptions()
                    options.isSynchronous = true
                    imageManager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 100, height: 100),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        DispatchQueue.main.async { onThumbnail(image) }
                    }
                }

                self.writeAsset(
                    asset,
                    to: fileURL,
                    includeLivePhotosAsVideo: includeLivePhotosAsVideo
                )
                filesWritten += 1

                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attributes[.size] as? Int64 {
                    currentTotalSize += size
                }

                DispatchQueue.main.async {
                    onProgress(processed, totalWork, "Copied \(processed) of \(totalWork)…")
                }
            }

            let folderCount =
                (try? FileManager.default.contentsOfDirectory(atPath: backupFolderURL.path).count) ?? 0
            let canceled = isCanceled()
            let outcome = BackupOutcome(
                filesWritten: filesWritten,
                canceled: canceled,
                totalSizeBytes: currentTotalSize,
                totalItemsInFolder: folderCount
            )

            DispatchQueue.main.async {
                backupFolderURL.stopAccessingSecurityScopedResource()
                onThumbnail(nil)
                completion(.success(outcome))
            }
        }
    }

    private func writeAsset(_ asset: PHAsset, to url: URL, includeLivePhotosAsVideo: Bool) {
        if asset.mediaType == .image {
            writeImageAsset(asset, to: url, backupLivePhotoAsVideo: includeLivePhotosAsVideo)
        } else if asset.mediaType == .video {
            writeVideoAsset(asset, to: url)
        }
        appendAssetMetadata(asset, to: url)
    }

    private func writeImageAsset(_ asset: PHAsset, to url: URL, backupLivePhotoAsVideo: Bool) {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true
        requestOptions.isNetworkAccessAllowed = true

        imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
            if let data = data {
                do {
                    try data.write(to: url)
                } catch {
                    print("Error writing file: \(error)")
                }
            }
        }

        if backupLivePhotoAsVideo, asset.mediaSubtypes.contains(.photoLive) {
            let liveVideoURL = url.deletingPathExtension().appendingPathExtension("mov")
            let sem = DispatchSemaphore(value: 0)
            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            imageManager.requestLivePhoto(
                for: asset,
                targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, _ in
                guard let livePhoto = livePhoto else {
                    sem.signal()
                    return
                }
                let resources = PHAssetResource.assetResources(for: livePhoto)
                if let videoResource = resources.first(where: { $0.type == .pairedVideo }) {
                    PHAssetResourceManager.default().writeData(
                        for: videoResource,
                        toFile: liveVideoURL,
                        options: nil
                    ) { _ in
                        sem.signal()
                    }
                } else {
                    sem.signal()
                }
            }
            sem.wait()
        }
    }

    private func writeVideoAsset(_ asset: PHAsset, to url: URL) {
        let sem = DispatchSemaphore(value: 0)
        let imageManager = PHImageManager.default()
        let requestOptions = PHVideoRequestOptions()
        requestOptions.isNetworkAccessAllowed = true

        imageManager.requestAVAsset(forVideo: asset, options: requestOptions) { avAsset, _, _ in
            defer { sem.signal() }
            if let avAsset = avAsset as? AVURLAsset {
                do {
                    try FileManager.default.copyItem(at: avAsset.url, to: url)
                } catch {
                    print("Error writing file: \(error)")
                }
            }
        }
        sem.wait()
    }

    private func appendAssetMetadata(_ asset: PHAsset, to url: URL) {
        let creationDate = asset.creationDate ?? Date()
        let modificationDate = asset.modificationDate ?? Date()
        do {
            let attributes: [FileAttributeKey: Any] = [
                .creationDate: creationDate,
                .modificationDate: modificationDate,
            ]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            print("Error setting file attributes: \(error)")
        }
    }

    /// Removes all items inside the folder but keeps the folder node (preserves security-scoped URL).
    func clearFolderContents(
        backupFolderURL: URL,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard backupFolderURL.startAccessingSecurityScopedResource() else {
            completion(.failure(BackupManagerError.securityScopeDenied))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            defer { backupFolderURL.stopAccessingSecurityScopedResource() }
            do {
                let items = try FileManager.default.contentsOfDirectory(
                    at: backupFolderURL,
                    includingPropertiesForKeys: nil
                )
                for item in items {
                    try FileManager.default.removeItem(at: item)
                }
                DispatchQueue.main.async {
                    completion(.success(items.count))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
