import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var includePhotos = true
    @State private var includeVideos = true
    @State private var includeLivePhotosAsVideo = true
    @State private var showThumbnail = true

    var body: some View {
        mainScrollView
            .sheet(isPresented: $viewModel.showDocumentPicker) {
                DocumentPicker { url in
                    viewModel.userPickedBackupFolder(url)
                }
            }
            .onAppear(perform: handleAppear)
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
            .alert(item: alertItemBinding) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Backup folder", isPresented: bookmarkNoticePresented, actions: {
                Button("OK", role: .cancel) { viewModel.dismissBookmarkNotice() }
            }, message: {
                Text(viewModel.folderBookmarkStaleNotice ?? "")
            })
            .confirmationDialog(
                "Clear backup folder?",
                isPresented: clearFolderDialogPresented,
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
                isPresented: deleteDuplicatesDialogPresented,
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

    // MARK: - Main stack (split for Swift compiler / previews)

    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroSection
                chooseBackupFolderCallout
                libraryStatsSection
                backupSettingsSection
                backupMetadataSection
                primaryBackupButton
                backupDestinationSection
                backupProgressSection
                clearFolderButton
                deduplicationSection
            }
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder private var heroSection: some View {
        Image("AppHomeIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 200, height: 200)
            .accessibilityHidden(true)
    }

    /// Shown only when no folder bookmark is saved yet.
    @ViewBuilder private var chooseBackupFolderCallout: some View {
        if !viewModel.isBackupInProgress, viewModel.state.backupFolderBookmark == nil {
            Button("Choose backup folder") {
                viewModel.showDocumentPicker = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Choose where exported photos and videos are saved.")
        }
    }

    /// Shown when a destination is already saved; name resolves when the bookmark is valid.
    @ViewBuilder private var backupDestinationSection: some View {
        if !viewModel.isBackupInProgress, viewModel.state.backupFolderBookmark != nil {
            GroupBox("Backup destination") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = viewModel.backupFolderDisplayName {
                            Text(name)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Folder could not be opened")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Tap Change to pick the folder again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Change") {
                        viewModel.showDocumentPicker = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Change backup folder")
                    .accessibilityHint("Pick a different folder for backups.")
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var libraryStatsSection: some View {
        Text("Photos: \(viewModel.totalPhotosCount), videos: \(viewModel.totalVideosCount)")
            .font(.subheadline)
            .accessibilityElement(children: .combine)

        HStack(alignment: .center) {
            Text(missingCountsLabel)
                .font(.subheadline)
                .accessibilityLabel(missingCountsAccessibilityLabel)
            Spacer(minLength: 8)
            Button {
                viewModel.refreshMissingCounts()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh missing counts")
        }
        .padding(.horizontal)
    }

    private var missingCountsLabel: String {
        "Missing — photos: \(viewModel.totalMissingPhotosCount), videos: \(viewModel.totalMissingVideosCount)"
    }

    private var missingCountsAccessibilityLabel: String {
        "Missing from backup: \(viewModel.totalMissingPhotosCount) photos, \(viewModel.totalMissingVideosCount) videos"
    }

    @ViewBuilder private var backupSettingsSection: some View {
        GroupBox("Backup settings") {
            Toggle("Include photos", isOn: $includePhotos)
            Toggle("Include videos", isOn: $includeVideos)
            Toggle("Export Live Photos as video", isOn: $includeLivePhotosAsVideo)
            Toggle("Show thumbnail while copying", isOn: $showThumbnail)
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var backupMetadataSection: some View {
        if let date = viewModel.state.lastBackupDate {
            Text("Last backup: \(date, style: .date)")
                .font(.subheadline)
        }
        Text(totalBackupSizeLabel)
            .font(.subheadline)
    }

    private var totalBackupSizeLabel: String {
        let formatted = ByteCountFormatter.string(
            fromByteCount: viewModel.state.totalBackupSize,
            countStyle: .file
        )
        return "Total backup size: \(formatted)"
    }

    @ViewBuilder private var primaryBackupButton: some View {
        if !viewModel.isBackupInProgress {
            Button("Back up library") {
                viewModel.startBackup()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Copies new items from your library into the selected folder.")
        }
    }

    @ViewBuilder private var backupProgressSection: some View {
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
    }

    @ViewBuilder private var clearFolderButton: some View {
        if !viewModel.isBackupInProgress {
            Button("Clear folder contents") {
                viewModel.requestClearFolder()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityHint("Deletes every file inside the backup folder.")
        }
    }

    @ViewBuilder private var deduplicationSection: some View {
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

    // MARK: - Bindings (ease type checker)

    private var alertItemBinding: Binding<ArchiveAngelAlert?> {
        Binding(
            get: { viewModel.alert },
            set: { viewModel.alert = $0 }
        )
    }

    private var bookmarkNoticePresented: Binding<Bool> {
        Binding(
            get: { viewModel.folderBookmarkStaleNotice != nil },
            set: { if !$0 { viewModel.dismissBookmarkNotice() } }
        )
    }

    private var clearFolderDialogPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeDialog == .clearFolder },
            set: { new in
                if !new { viewModel.activeDialog = nil }
            }
        )
    }

    private var deleteDuplicatesDialogPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeDialog == .deleteDuplicates },
            set: { new in
                if !new { viewModel.cancelDuplicateDeletionDialog() }
            }
        )
    }

    private func handleAppear() {
        syncTogglesFromState()
        viewModel.refreshMediaCounts()
        viewModel.refreshMissingCounts()
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
