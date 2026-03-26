import Foundation
import Photos

/// Photo-only deduplication using SHA-256 of full image data. Videos are skipped.
final class DeduplicationManager {

    func scanDuplicatePhotos(
        isCanceled: @escaping () -> Bool,
        onProgress: @escaping (_ processed: Int, _ total: Int, _ message: String) -> Void,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            let total = assets.count

            var assetHashes: [String: String] = [:]
            var duplicates: [String] = []
            let progressQueue = DispatchQueue(label: "com.archiveangel.dedup.progress")
            var completed = 0

            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.isSynchronous = false

            let batchSize = 32
            var index = 0

            while index < total {
                if isCanceled() {
                    DispatchQueue.main.async {
                        completion(.failure(CancellationError()))
                    }
                    return
                }

                let end = min(index + batchSize, total)
                let group = DispatchGroup()

                for i in index..<end {
                    if isCanceled() { break }
                    let asset = assets.object(at: i)
                    group.enter()
                    imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) {
                        data,
                        _,
                        _,
                        _ in
                        defer { group.leave() }
                        if let data = data {
                            let hash = CryptoHelpers.sha256Hex(data)
                            if let _ = assetHashes[hash] {
                                duplicates.append(asset.localIdentifier)
                            } else {
                                assetHashes[hash] = asset.localIdentifier
                            }
                        }
                        progressQueue.sync {
                            completed += 1
                            let c = completed
                            DispatchQueue.main.async {
                                onProgress(c, total, "Scanning \(c) of \(total) photos…")
                            }
                        }
                    }
                }

                group.wait()
                index = end
            }

            if isCanceled() {
                DispatchQueue.main.async {
                    completion(.failure(CancellationError()))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.success(duplicates))
            }
        }
    }

    func deleteAssets(
        localIdentifiers: [String],
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard !localIdentifiers.isEmpty else {
            completion(.success(0))
            return
        }
        let toDelete = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(toDelete)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else if success {
                    completion(.success(localIdentifiers.count))
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "ArchiveAngel",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Photo library change failed."]
                            )
                        )
                    )
                }
            }
        })
    }
}
