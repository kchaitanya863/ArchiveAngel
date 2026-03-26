import Photos
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var includePhotos = true
    @State private var includeVideos = true
    @State private var includeLivePhotosAsVideo = true
    @State private var showThumbnail = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("AppHomeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .accessibilityHidden(true)

                if !viewModel.isBackupInProgress {
                    Button("Select backup folder") {
                        viewModel.showDocumentPicker = true
                    }
                    .accessibilityHint("Choose where exported photos and videos are saved.")
                    .sheet(isPresented: $viewModel.showDocumentPicker) {
                        DocumentPicker { url in
                            viewModel.userPickedBackupFolder(url)
                        }
                    }
                }

                Text("Photos: \(viewModel.totalPhotosCount), videos: \(viewModel.totalVideosCount)")
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)

                HStack(alignment: .center) {
                    Text(
                        "Missing — photos: \(viewModel.totalMissingPhotosCount), videos: \(viewModel.totalMissingVideosCount)"
                    )
                    .font(.subheadline)
                    .accessibilityLabel(
                        "Missing from backup: \(viewModel.totalMissingPhotosCount) photos, \(viewModel.totalMissingVideosCount) videos"
                    )
                    Spacer(minLength: 8)
                    Button {
                        viewModel.refreshMissingCounts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh missing counts")
                }
                .padding(.horizontal)

                GroupBox("Backup settings") {
                    Toggle("Include photos", isOn: $includePhotos)
                    Toggle("Include videos", isOn: $includeVideos)
                    Toggle("Export Live Photos as video", isOn: $includeLivePhotosAsVideo)
                    Toggle("Show thumbnail while copying", isOn: $showThumbnail)
                }
                .padding(.horizontal)

                if let date = viewModel.state.lastBackupDate {
                    Text("Last backup: \(date, style: .date)")
                        .font(.subheadline)
                }
                Text(
                    "Total backup size: \(ByteCountFormatter.string(fromByteCount: viewModel.state.totalBackupSize, countStyle: .file))"
                )
                .font(.subheadline)

                if !viewModel.isBackupInProgress {
                    Button("Back up library") {
                        viewModel.startBackup()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Copies new items from your library into the selected folder.")
                }

                if let name = viewModel.backupFolderDisplayName {
                    Text("Backup folder: \(name)")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if viewModel.isBackupInProgress, let thumbnail = viewModel.currentThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                        .accessibilityLabel("Current item thumbnail")
                    Text(viewModel.progressMessage)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding(.horizontal)
                }

                if viewModel.isBackupInProgress {
                    ProgressView(value: viewModel.backupProgress, total: 100)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                        .accessibilityLabel("Backup progress")
                    Button("Cancel backup") {
                        viewModel.cancelBackup()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if !viewModel.isBackupInProgress {
                    Button("Clear folder contents") {
                        viewModel.requestClearFolder()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityHint("Deletes every file inside the backup folder.")
                }

                if !viewModel.isDedupScanInProgress {
                    Button("Scan for duplicate photos") {
                        viewModel.startDuplicateScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .accessibilityHint("Finds duplicate images by file content. Videos are ignored.")
                }

                if viewModel.isDedupScanInProgress {
                    ProgressView(value: viewModel.dedupProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                    Text(viewModel.dedupMessage)
                        .font(.caption)
                        .padding(.horizontal)
                    Button("Cancel") {
                        if viewModel.scannedDuplicateLocalIds.isEmpty {
                            viewModel.cancelDedupScan()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!viewModel.scannedDuplicateLocalIds.isEmpty)
                }
            }
            .padding(.vertical, 24)
        }
        .onAppear {
            syncTogglesFromState()
            viewModel.refreshMediaCounts()
            viewModel.refreshMissingCounts()
        }
        .onChange(of: includePhotos) { _ in pushSettings() }
        .onChange(of: includeVideos) { _ in pushSettings() }
        .onChange(of: includeLivePhotosAsVideo) { _ in pushSettings() }
        .onChange(of: showThumbnail) { _ in pushSettings() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                viewModel.refreshMediaCounts()
                viewModel.refreshMissingCounts()
            }
        }
        .alert(item: Binding(
            get: { viewModel.alert },
            set: { viewModel.alert = $0 }
        )) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Backup folder", isPresented: Binding(
            get: { viewModel.folderBookmarkStaleNotice != nil },
            set: { if !$0 { viewModel.dismissBookmarkNotice() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissBookmarkNotice() }
        } message: {
            Text(viewModel.folderBookmarkStaleNotice ?? "")
        }
        .confirmationDialog(
            "Clear backup folder?",
            isPresented: Binding(
                get: { viewModel.activeDialog == .clearFolder },
                set: { new in
                    if !new { viewModel.activeDialog = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete all files inside folder", role: .destructive) {
                viewModel.performClearFolder()
            }
            Button("Cancel", role: .cancel) { viewModel.activeDialog = nil }
        } message: {
            Text("The folder stays selected; only its contents are removed.")
        }
        .confirmationDialog(
            "Delete duplicate photos?",
            isPresented: Binding(
                get: { viewModel.activeDialog == .deleteDuplicates },
                set: { new in
                    if !new { viewModel.cancelDuplicateDeletionDialog() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(viewModel.scannedDuplicateLocalIds.count) photos", role: .destructive) {
                viewModel.confirmDeleteScannedDuplicates()
            }
            Button("Cancel", role: .cancel) { viewModel.cancelDuplicateDeletionDialog() }
        } message: {
            Text("One copy of each matching image is kept. Videos are not scanned. This cannot be undone.")
        }
    }

    private func syncTogglesFromState() {
        includePhotos = viewModel.state.includePhotos
        includeVideos = viewModel.state.includeVideos
        includeLivePhotosAsVideo = viewModel.state.includeLivePhotosAsVideo
        showThumbnail = viewModel.state.showThumbnail
    }

    private func pushSettings() {
        viewModel.applySettingsFromUI(
            includePhotos: includePhotos,
            includeVideos: includeVideos,
            includeLivePhotosAsVideo: includeLivePhotosAsVideo,
            showThumbnail: showThumbnail
        )
        viewModel.refreshMissingCounts()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
