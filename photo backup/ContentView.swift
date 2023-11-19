import Photos
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var backupFolderURL: URL?
  @State private var showDocumentPicker = false

  @State private var isBackupInProgress = false
  @State private var backupProgress: Double = 0.0

  @State private var showingAlert = false
  @State private var completionMessage: String = ""
  @State private var progressMessage: String = ""
  @State private var currentThumbnail: UIImage?

  @State private var includePhotos = true
  @State private var includeVideos = true
  @State private var includeLivePhotosAsVideo = true

  @State private var totalPhotosCount = 0
  @State private var totalVideosCount = 0

  @State private var totalMissingPhotosCount = 0
  @State private var totalMissingVideosCount = 0

  @State private var showThumbnail = false

  @State private var cancelBackup = false

  private func fetchMediaCounts() {
    let photosOptions = PHFetchOptions()
    photosOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
    totalPhotosCount = PHAsset.fetchAssets(with: photosOptions).count

    let videosOptions = PHFetchOptions()
    videosOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
    totalVideosCount = PHAsset.fetchAssets(with: videosOptions).count
  }

  private func calculateMissingMediaCounts(url: URL) {
    totalMissingPhotosCount = 0
    totalMissingVideosCount = 0
    let fetchOptions = PHFetchOptions()
    let assets = PHAsset.fetchAssets(with: fetchOptions)
    assets.enumerateObjects { (asset, index, stop) in
      if asset.mediaType == .image && !includePhotos {
        return
      }

      if asset.mediaType == .video && !includeVideos {
        return
      }

      let filename = asset.value(forKey: "filename") as? String ?? "unknown"
      let fileURL = url.appendingPathComponent(
        asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + filename)

      if !FileManager.default.fileExists(atPath: fileURL.path) {
        if asset.mediaType == .image {
          totalMissingPhotosCount += 1
        } else if asset.mediaType == .video {
          totalMissingVideosCount += 1
        }
      }
    }
  }

  private func showConfirmationAlert() {
    let alert = UIAlertController(
      title: "Clear Backup Folder",
      message: "Are you sure you want to clear the backup folder?",
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: "Yes", style: .default) { _ in
        clearTargetFolder()
      })
    alert.addAction(UIAlertAction(title: "No", style: .cancel))
    UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
  }

  private func writeImageAsset(_ asset: PHAsset, to url: URL, backupLivePhotoAsVideo: Bool = false)
  {
    let imageManager = PHImageManager.default()
    let requestOptions = PHImageRequestOptions()
    requestOptions.isSynchronous = true  // Keep synchronous for image data

    // Request image data and write to file
    imageManager.requestImageDataAndOrientation(
      for: asset,
      options: requestOptions
    ) { data, _, _, _ in
      if let data = data {
        do {
          try data.write(to: url)
        } catch {
          print("Error writing file: \(error)")
        }
      }
    }

    // Process live photo's video component synchronously
    if backupLivePhotoAsVideo && asset.mediaSubtypes.contains(.photoLive) {
      let options = PHLivePhotoRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat
      print("asset address: \(asset)")
      let liveVideoFilename = url.deletingPathExtension().appendingPathExtension("mov")

      imageManager.requestLivePhoto(
        for: asset, targetSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
        contentMode: .aspectFit, options: options
      ) { livePhoto, _ in
        guard let livePhoto = livePhoto else { return }

        // Accessing the resource file for the Live Photo
        let resources = PHAssetResource.assetResources(for: livePhoto)
        if let videoResource = resources.first(where: { $0.type == .pairedVideo }) {
          // Write the video part of the Live Photo to the URL
          print("videoResource: \(videoResource)")
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

    imageManager.requestAVAsset(
      forVideo: asset,
      options: PHVideoRequestOptions()
    ) { avAsset, _, _ in
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
    // get the original asset date created and modified
    let creationDate = asset.creationDate ?? Date()
    let modificationDate = asset.modificationDate ?? Date()

    // set the file attributes
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

  private func writeAsset(_ asset: PHAsset, to url: URL) {
    print("asset address: \(asset)")
    if asset.mediaType == .image {
      writeImageAsset(asset, to: url, backupLivePhotoAsVideo: includeLivePhotosAsVideo)
    } else if asset.mediaType == .video {
      writeVideoAsset(asset, to: url)
    }
    // Always append the metadata
    appendAssetMetadata(asset, to: url)
  }

  private func startBackupProcess() {
    guard let backupFolderURL = backupFolderURL else {
      showingAlert = true
      completionMessage = "Backup failed: No backup folder selected."
      return
    }

    guard backupFolderURL.startAccessingSecurityScopedResource() else {
      print("Error: Unable to start accessing security-scoped resource.")
      completionMessage = "Backup failed: Unable to access selected backup folder."
      showingAlert = true
      return
    }

    isBackupInProgress = true
    backupProgress = 0.0
    cancelBackup = false

    DispatchQueue.global(qos: .userInitiated).async {
      let fetchOptions = PHFetchOptions()

      let assets = PHAsset.fetchAssets(with: fetchOptions)
      let assetsCount = assets.count
      var filesWrittenCount = 0

      let imageManager = PHImageManager.default()
      let requestOptions = PHImageRequestOptions()
      requestOptions.isSynchronous = true  // Consider asynchronous for production

      assets.enumerateObjects { (asset, index, stop) in
        if self.cancelBackup {
          stop.pointee = true
          return
        }

        if asset.mediaType == .image && !self.includePhotos {
          return
        }

        if asset.mediaType == .video && !self.includeVideos {
          return
        }

        let filename = asset.value(forKey: "filename") as? String ?? "unknown"
        let fileURL = backupFolderURL.appendingPathComponent(
          asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
          print("File already exists: \(fileURL.path)")
          return
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = true  // Consider asynchronous for production

        if showThumbnail {
          imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: options
          ) { image, _ in
            if let image = image {
              self.currentThumbnail = image
            }
          }
        }

        self.writeAsset(asset, to: fileURL)

        self.progressMessage = "Copied \(index + 1) file\(index == 1 ? "": "s")..."
        filesWrittenCount += 1

        DispatchQueue.main.async {
          self.backupProgress = Double(index + 1) / Double(assetsCount) * 100.0
        }
      }

      DispatchQueue.main.async {
        self.isBackupInProgress = false
        self.currentThumbnail = nil
        self.progressMessage = ""
        backupFolderURL.stopAccessingSecurityScopedResource()

        if self.cancelBackup {
          self.completionMessage = "Backup canceled."
          self.cancelBackup = false
        } else {
          let totalFiles =
            (try? FileManager.default.contentsOfDirectory(atPath: backupFolderURL.path).count) ?? 0
          self.completionMessage =
            "Copying complete. Files written: \(filesWrittenCount), Total files in folder: \(totalFiles)"
        }
      }
    }
  }

  private func clearTargetFolder() {
    guard let backupFolderURL = backupFolderURL else {
      showingAlert = true
      completionMessage = "Backup failed: No backup folder selected."
      return
    }

    guard backupFolderURL.startAccessingSecurityScopedResource() else {
      print("Error: Unable to start accessing security-scoped resource.")
      completionMessage = "Backup failed: Unable to access selected backup folder."
      showingAlert = true
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      // Delete folder and recreate it
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

  var body: some View {
    ScrollView {
      VStack {
        Spacer()

        Image("AppHomeIcon")
          .resizable()  // Make it resizable
          .aspectRatio(contentMode: .fit)  // Maintain aspect ratio
          .frame(width: 200, height: 200)  // Adjust the size as needed

        // Only show the 'Select Backup Folder' button if the backup is not in progress
        if !isBackupInProgress {
          Button("Select Backup Folder") {
            showDocumentPicker = true
          }
          .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
              backupFolderURL = url
            }
          }
        }

        Text("Photos: \(totalPhotosCount), Videos: \(totalVideosCount)")
          .onAppear(perform: fetchMediaCounts)

        Text(
          "Missing Photos: \(totalMissingPhotosCount), Missing Videos: \(totalMissingVideosCount)"
        )
        .onAppear(perform: {
          if let backupFolderURL = backupFolderURL {
            calculateMissingMediaCounts(url: backupFolderURL)
          }
        })
        .onTapGesture {
          if let backupFolderURL = backupFolderURL {
            calculateMissingMediaCounts(url: backupFolderURL)
          }
        }
        .padding()

        VStack {
          HStack {
            Text("Include Photos")
            Spacer()
            Toggle("", isOn: $includePhotos)
          }
          .padding()

          HStack {
            Text("Include Videos")
            Spacer()
            Toggle("", isOn: $includeVideos)
          }
          .padding()

          HStack {
            Text("Include Live Photos as Video")
            Spacer()
            Toggle("", isOn: $includeLivePhotosAsVideo)
          }
          .padding()

          HStack {
            Text("Show Thumbnail when Copying")
            Spacer()
            Toggle("", isOn: $showThumbnail)
          }
          .padding()
        }
        // Only show the 'Backup Photos' button if the backup is not in progress
        if !isBackupInProgress {
          Button("Backup Photos") {
            startBackupProcess()
          }
          .padding()
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(8)
          .alert(isPresented: $showingAlert) {
            Alert(
              title: Text("No Folder Selected"),
              message: Text("Please select a folder to backup your photos."),
              dismissButton: .default(Text("OK"))
            )
          }
          .alert(
            isPresented: Binding<Bool>(
              get: { !completionMessage.isEmpty },
              set: { _ in completionMessage = "" }
            )
          ) {
            Alert(
              title: Text("Backup Complete"), message: Text(completionMessage),
              dismissButton: .default(Text("OK")))
          }
        }

        if let url = backupFolderURL {
          Text("Backup to: \(url.lastPathComponent)")
            .font(.caption)
            .padding()
            .multilineTextAlignment(.center)
        }

        if isBackupInProgress, let thumbnail = currentThumbnail {
          Image(uiImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 100, height: 100)  // Adjust the size as needed
            .clipped()
            .cornerRadius(8)
            .padding()
          Text(progressMessage)
            .lineLimit(2)  // Limit to two lines
            .truncationMode(.tail)  // Add ellipses at the end if the text is too long
            .padding()
        }

        if isBackupInProgress {
          ProgressView(value: backupProgress, total: 100)
            .progressViewStyle(LinearProgressViewStyle())
            .padding()
        }

        if isBackupInProgress {
          Button("Cancel Backup") {
            cancelBackup = true
          }
          .padding()
          .background(Color.red)
          .foregroundColor(.white)
          .cornerRadius(8)
        }

        if !isBackupInProgress {
          Button("Clear Backup Folder") {
            showConfirmationAlert()
          }
          .padding()
          .background(Color.red)
          .foregroundColor(.white)
          .cornerRadius(8)
        }
        Spacer()
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
