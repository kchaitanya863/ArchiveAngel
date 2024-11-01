import SwiftUI
import Photos

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
    @State private var isDedupInProgress = false
    @State private var dedupProgress: Double = 0.0
    @State private var dedupMessage: String = ""
    @State private var cancelDedup = false

    private let backupManager = BackupManager()
    private let deduplicationManager = DeduplicationManager()

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

    var body: some View {
        ScrollView {
            VStack {
                Spacer()

                Image("AppHomeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)

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

                HStack {
                    Text(
                        "Missing Photos: \(totalMissingPhotosCount), Missing Videos: \(totalMissingVideosCount)"
                    )
                    .onAppear(perform: {
                        if let backupFolderURL = backupFolderURL {
                            calculateMissingMediaCounts(url: backupFolderURL)
                        }
                    })
                    
                    Button(action: {
                        if let backupFolderURL = backupFolderURL {
                            calculateMissingMediaCounts(url: backupFolderURL)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
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

//                Button("Star this project on GitHub 💻") {
//                    UIApplication.shared.open(URL(string: "https://github.com/kchaitanya863/ArchiveAngel")!)
//                }
//                .padding()
//                .background(Color.white)
//                .foregroundColor(.black)
//                .cornerRadius(8)
                
                if !isBackupInProgress {
                    Button("Backup Photos 💾") {
                        backupManager.startBackupProcess(
                            backupFolderURL: backupFolderURL,
                            includePhotos: includePhotos,
                            includeVideos: includeVideos,
                            includeLivePhotosAsVideo: includeLivePhotosAsVideo,
                            showThumbnail: showThumbnail,
                            isBackupInProgress: $isBackupInProgress,
                            backupProgress: $backupProgress,
                            cancelBackup: $cancelBackup,
                            currentThumbnail: $currentThumbnail,
                            progressMessage: $progressMessage,
                            completionMessage: $completionMessage,
                            showingAlert: $showingAlert
                        )
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
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                        .padding()
                    Text(progressMessage)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding()
                }

                if isBackupInProgress {
                    ProgressView(value: backupProgress, total: 100)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding()
                }

                if isBackupInProgress {
                    Button("Cancel Backup 🛑") {
                        cancelBackup = true
                    }
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                if !isBackupInProgress {
                    Button("Clear Destination Folder ⚠️") {
                        backupManager.showConfirmationAlert(
                            backupFolderURL: backupFolderURL,
                            showingAlert: $showingAlert,
                            completionMessage: $completionMessage
                        )
                    }
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                if !isDedupInProgress {
                    Button("Delete Duplicate Photos 📸") {
                        deduplicationManager.deleteDuplicatePhotos(
                            isDedupInProgress: $isDedupInProgress,
                            dedupProgress: $dedupProgress,
                            dedupMessage: $dedupMessage,
                            cancelDedup: $cancelDedup,
                            fetchMediaCounts: fetchMediaCounts
                        )
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                if isDedupInProgress {
                    ProgressView(value: dedupProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding()
                    Text(dedupMessage)
                        .padding()
                    Button("Cancel Deduplication 🛑") {
                        cancelDedup = true
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
