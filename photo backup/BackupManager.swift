import Photos
import SwiftUI
import UIKit

class BackupManager {
    func startBackupProcess(
        backupFolderURL: URL?,
        includePhotos: Bool,
        includeVideos: Bool,
        includeLivePhotosAsVideo: Bool,
        showThumbnail: Bool,
        isBackupInProgress: Binding<Bool>,
        backupProgress: Binding<Double>,
        cancelBackup: Binding<Bool>,
        currentThumbnail: Binding<UIImage?>,
        progressMessage: Binding<String>,
        completionMessage: Binding<String>,
        showingAlert: Binding<Bool>,
        totalBackupSize: Binding<Int64>,
        lastBackupDate: Binding<Date?>
    ) {
        guard let backupFolderURL = backupFolderURL else {
            showingAlert.wrappedValue = true
            completionMessage.wrappedValue = "Backup failed: No backup folder selected."
            return
        }

        guard backupFolderURL.startAccessingSecurityScopedResource() else {
            print("Error: Unable to start accessing security-scoped resource.")
            completionMessage.wrappedValue = "Backup failed: Unable to access selected backup folder."
            showingAlert.wrappedValue = true
            return
        }

        isBackupInProgress.wrappedValue = true
        backupProgress.wrappedValue = 0.0
        cancelBackup.wrappedValue = false
        var currentTotalSize: Int64 = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()

            let assets = PHAsset.fetchAssets(with: fetchOptions)
            let assetsCount = assets.count
            var filesWrittenCount = 0

            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true

            assets.enumerateObjects { (asset, index, stop) in
                if cancelBackup.wrappedValue {
                    stop.pointee = true
                    return
                }

                if asset.mediaType == .image && !includePhotos {
                    return
                }

                if asset.mediaType == .video && !includeVideos {
                    return
                }

                let filename = asset.value(forKey: "filename") as? String ?? "unknown"
                let fileURL = backupFolderURL.appendingPathComponent(
                    asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + filename)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let size = attributes[.size] as? Int64 {
                        currentTotalSize += size
                    }
                    return
                }

                let options = PHImageRequestOptions()
                options.isSynchronous = true

                if showThumbnail {
                    imageManager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 100, height: 100),
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        if let image = image {
                            currentThumbnail.wrappedValue = image
                        }
                    }
                }

                self.writeAsset(asset, to: fileURL, includeLivePhotosAsVideo: includeLivePhotosAsVideo)

                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attributes[.size] as? Int64 {
                    currentTotalSize += size
                    DispatchQueue.main.async {
                        totalBackupSize.wrappedValue = currentTotalSize
                    }
                }

                progressMessage.wrappedValue = "Copied \(index + 1) file\(index == 1 ? "": "s")..."
                filesWrittenCount += 1

                DispatchQueue.main.async {
                    backupProgress.wrappedValue = Double(index + 1) / Double(assetsCount) * 100.0
                }
            }

            DispatchQueue.main.async {
                isBackupInProgress.wrappedValue = false
                currentThumbnail.wrappedValue = nil
                progressMessage.wrappedValue = ""
                backupFolderURL.stopAccessingSecurityScopedResource()

                totalBackupSize.wrappedValue = currentTotalSize
                lastBackupDate.wrappedValue = Date()

                if cancelBackup.wrappedValue {
                    completionMessage.wrappedValue = "Backup canceled."
                    cancelBackup.wrappedValue = false
                } else {
                    let totalFiles =
                        (try? FileManager.default.contentsOfDirectory(atPath: backupFolderURL.path).count) ?? 0
                    completionMessage.wrappedValue =
                        "Copying complete. Files written: \(filesWrittenCount), Total files in folder: \(totalFiles)"
                }

                NotificationCenter.default.post(name: NSNotification.Name("SaveBackupInfo"), object: nil)
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

    private func writeImageAsset(_ asset: PHAsset, to url: URL, backupLivePhotoAsVideo: Bool = false) {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = true

        imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { data, _, _, _ in
            if let data = data {
                do {
                    try data.write(to: url)
                } catch {
                    print("Error writing file: \(error)")
                }
            }
        }

        if backupLivePhotoAsVideo && asset.mediaSubtypes.contains(.photoLive) {
            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            let liveVideoFilename = url.deletingPathExtension().appendingPathExtension("mov")

            imageManager.requestLivePhoto(
                for: asset, targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                contentMode: .aspectFit, options: options
            ) { livePhoto, _ in
                guard let livePhoto = livePhoto else { return }

                let resources = PHAssetResource.assetResources(for: livePhoto)
                if let videoResource = resources.first(where: { $0.type == .pairedVideo }) {
                    PHAssetResourceManager.default().writeData(
                        for: videoResource, toFile: liveVideoFilename, options: nil
                    ) { error in
                        if let error = error {
                            print("Error writing Live Photo video: \(error)")
                        }
                    }
                }
            }
        }
    }

    private func writeVideoAsset(_ asset: PHAsset, to url: URL) {
        let imageManager = PHImageManager.default()
        let requestOptions = PHVideoRequestOptions()
        requestOptions.isNetworkAccessAllowed = true

        imageManager.requestAVAsset(forVideo: asset, options: requestOptions) { avAsset, _, _ in
            if let avAsset = avAsset as? AVURLAsset {
                do {
                    try FileManager.default.copyItem(at: avAsset.url, to: url)
                } catch {
                    print("Error writing file: \(error)")
                }
            }
        }
    }

    private func appendAssetMetadata(_ asset: PHAsset, to url: URL) {
        let creationDate = asset.creationDate ?? Date()
        let modificationDate = asset.modificationDate ?? Date()

        do {
            let attributes = [
                FileAttributeKey.creationDate: creationDate,
                FileAttributeKey.modificationDate: modificationDate,
            ]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            print("Error setting file attributes: \(error)")
        }
    }

    func showConfirmationAlert(
        backupFolderURL: URL?,
        showingAlert: Binding<Bool>,
        completionMessage: Binding<String>
    ) {
        let alert = UIAlertController(
            title: "Clear Backup Folder",
            message: "Are you sure you want to clear the backup folder?",
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "Yes", style: .default) { _ in
                self.clearTargetFolder(
                    backupFolderURL: backupFolderURL,
                    showingAlert: showingAlert,
                    completionMessage: completionMessage
                )
            })
        alert.addAction(UIAlertAction(title: "No", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
    }

    private func clearTargetFolder(
        backupFolderURL: URL?,
        showingAlert: Binding<Bool>,
        completionMessage: Binding<String>
    ) {
        guard let backupFolderURL = backupFolderURL else {
            showingAlert.wrappedValue = true
            completionMessage.wrappedValue = "Backup failed: No backup folder selected."
            return
        }

        guard backupFolderURL.startAccessingSecurityScopedResource() else {
            print("Error: Unable to start accessing security-scoped resource.")
            completionMessage.wrappedValue = "Backup failed: Unable to access selected backup folder."
            showingAlert.wrappedValue = true
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.removeItem(at: backupFolderURL)
                try FileManager.default.createDirectory(
                    at: backupFolderURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                print("Error deleting folder: \(error)")
            }
        }
    }
}
