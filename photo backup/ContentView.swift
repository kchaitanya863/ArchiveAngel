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

  @State private var totalPhotosCount = 0
  @State private var totalVideosCount = 0

  @State private var cancelBackup = false

  private func fetchMediaCounts() {
    let photosOptions = PHFetchOptions()
    photosOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
    totalPhotosCount = PHAsset.fetchAssets(with: photosOptions).count

    let videosOptions = PHFetchOptions()
    videosOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
    totalVideosCount = PHAsset.fetchAssets(with: videosOptions).count
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
      // Configure fetchOptions as needed

      if includePhotos && !includeVideos {
        fetchOptions.predicate = NSPredicate(
          format: "mediaType = %d", PHAssetMediaType.image.rawValue)
      } else if includeVideos && !includePhotos {
        fetchOptions.predicate = NSPredicate(
          format: "mediaType = %d", PHAssetMediaType.video.rawValue)
      }

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

        let safeFileName = asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + ".jpg"
        let fileURL = backupFolderURL.appendingPathComponent(safeFileName)

        let thumbnailSize = CGSize(width: 100, height: 100)  // Adjust the size as needed
        if !FileManager.default.fileExists(atPath: fileURL.path) {
          imageManager.requestImage(
            for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: requestOptions
          ) { (image, _) in
            DispatchQueue.main.async {
              self.currentThumbnail = image
              self.progressMessage = "Copying: \(safeFileName)"
            }
          }

          // Fetch the creation date from the asset
          let creationDate = asset.creationDate

          imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) {
            (data, dataUTI, orientation, info) in
            guard let data = data, let dataUTIString = dataUTI else { return }

            let fileExtension: String
            if let uti = UTType(dataUTIString),
              let preferredExtension = uti.preferredFilenameExtension
            {
              fileExtension = preferredExtension
            } else {
              fileExtension = "jpg"  // Default to jpg if the UTType can't be determined
            }

            let safeFileName =
              asset.localIdentifier.replacingOccurrences(of: "/", with: "_") + ".\(fileExtension)"
            let fileURL = backupFolderURL.appendingPathComponent(safeFileName)

            do {
              try data.write(to: fileURL)
              // Set the file's creation date attribute
              if let creationDate = creationDate {
                var attributes = [FileAttributeKey: Any]()
                attributes[.creationDate] = creationDate
                try FileManager.default.setAttributes(attributes, ofItemAtPath: fileURL.path)
              }
              filesWrittenCount += 1
            } catch {
              // Handle specific errors and update the UI
              DispatchQueue.main.async {
                self.showingAlert = true
                if let nsError = error as NSError? {
                  // Check for specific error codes and set a user-friendly message
                  switch nsError.code {
                  case NSFileWriteOutOfSpaceError:
                    self.completionMessage = "Backup failed: Out of disk space."
                  default:
                    self.completionMessage = "Backup failed: \(nsError.localizedDescription)"
                  }
                } else {
                  self.completionMessage = "Backup failed: An unknown error occurred."
                }
                print("Error writing file: \(error.localizedDescription)")  // Logging the error
              }
            }
          }
        }

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

  var body: some View {
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
        .padding()

      Toggle("Include Photos", isOn: $includePhotos)
        .padding()
      Toggle("Include Videos", isOn: $includeVideos)
        .padding()

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

      Spacer()
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
