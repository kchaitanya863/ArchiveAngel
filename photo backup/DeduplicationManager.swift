import Photos
import SwiftUI
import CommonCrypto

class DeduplicationManager {
    func deleteDuplicatePhotos(
        isDedupInProgress: Binding<Bool>,
        dedupProgress: Binding<Double>,
        dedupMessage: Binding<String>,
        cancelDedup: Binding<Bool>,
        fetchMediaCounts: @escaping () -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            let totalAssetsCount = assets.count

            var assetHashes: [String: String] = [:]
            var duplicates: [String] = []

            isDedupInProgress.wrappedValue = true
            dedupProgress.wrappedValue = 0.0
            cancelDedup.wrappedValue = false

            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .fastFormat
            requestOptions.resizeMode = .fast
            requestOptions.isSynchronous = false

            let batchSize = 50 // Process 50 assets at a time

            var currentIndex = 0

            while currentIndex < totalAssetsCount {
                if cancelDedup.wrappedValue {
                    DispatchQueue.main.async {
                        isDedupInProgress.wrappedValue = false
                        dedupMessage.wrappedValue = "Deduplication canceled."
                    }
                    break
                }

                let endIndex = min(currentIndex + batchSize, totalAssetsCount)
                let batchAssets = Array(currentIndex..<endIndex).map { assets.object(at: $0) }

                let group = DispatchGroup()

                for asset in batchAssets {
                    group.enter()

                    imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
                        if let data = data {
                            let hash = self.sha256(data)
                            if assetHashes[hash] != nil {
                                duplicates.append(asset.localIdentifier)
                                print("Duplicate found: \(asset.localIdentifier)")
                            } else {
                                assetHashes[hash] = asset.localIdentifier
                            }
                        }
                        DispatchQueue.main.async {
                            dedupProgress.wrappedValue = Double(currentIndex + 1) / Double(totalAssetsCount)
                            dedupMessage.wrappedValue = "Processing \(currentIndex + 1) of \(totalAssetsCount)..."
                        }
                        group.leave()
                    }

                    currentIndex += 1
                }

                group.wait() // Wait for the current batch to complete before proceeding to the next batch
            }

            DispatchQueue.main.async {
                guard !cancelDedup.wrappedValue else {
                    isDedupInProgress.wrappedValue = false
                    dedupMessage.wrappedValue = "Deduplication canceled."
                    return
                }

                let assetsToDelete = PHAsset.fetchAssets(withLocalIdentifiers: duplicates, options: nil)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets(assetsToDelete)
                }, completionHandler: { success, error in
                    if success {
                        print("Deleted duplicates successfully")
                        fetchMediaCounts()
                    } else if let error = error {
                        print("Error deleting duplicates: \(error)")
                    }
                    DispatchQueue.main.async {
                        isDedupInProgress.wrappedValue = false
                    }
                })
            }
        }
    }

    private func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
