import SwiftUI

/// Advanced backup options: media filters, export layout, and maintenance tools.
struct BackupSettingsView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel

    @State private var includePhotos = true
    @State private var includeVideos = true
    @State private var includeLivePhotosAsVideo = true
    @State private var showThumbnail = true
    @State private var backupFolderLayout = BackupFolderLayout.flat
    @State private var backupFileNaming = BackupFileNaming.identifierAndOriginal

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    backupSettingsSection
                    outputLayoutSection
                    maintenanceSection
                }
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: syncFromState)
        .onChange(of: viewModel.state) { _ in syncFromState() }
        .onChange(of: includePhotos) { _ in pushSettings() }
        .onChange(of: includeVideos) { _ in pushSettings() }
        .onChange(of: includeLivePhotosAsVideo) { _ in pushSettings() }
        .onChange(of: showThumbnail) { _ in pushSettings() }
        .onChange(of: backupFolderLayout) { _ in pushOutputSettings() }
        .onChange(of: backupFileNaming) { _ in pushOutputSettings() }
    }

    private var backupSettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("What to back up", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                Toggle("Include photos", isOn: $includePhotos)
                Toggle("Include videos", isOn: $includeVideos)
                Toggle("Export Live Photos as video", isOn: $includeLivePhotosAsVideo)
                Toggle("Show thumbnail while copying", isOn: $showThumbnail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Backup options", systemImage: "slider.horizontal.3")
        }
        .padding(.horizontal)
    }

    private var outputLayoutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose how files are organized under your backup folder and how they are named.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Folder structure", selection: $backupFolderLayout) {
                    ForEach(BackupFolderLayout.allCases) { layout in
                        Text(layout.menuTitle).tag(layout)
                    }
                }
                Picker("Filename pattern", selection: $backupFileNaming) {
                    ForEach(BackupFileNaming.allCases) { naming in
                        Text(naming.menuTitle).tag(naming)
                    }
                }
                Text(
                    "Date-based folders and the date-in-filename option use the asset’s creation time in UTC. New copies follow these rules; existing files in older layouts still count toward “missing” counts on the Backup tab."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Output layout & filenames", systemImage: "folder.badge.gearshape")
        }
        .padding(.horizontal)
    }

    private var maintenanceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("These actions affect your backup folder or photo library. Use them with care.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !viewModel.isBackupInProgress {
                    Button("Clear folder contents") {
                        viewModel.requestClearFolder()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Deletes every file inside the backup folder.")
                }

                if !viewModel.isDedupScanInProgress {
                    Button("Scan for duplicate photos") {
                        viewModel.startDuplicateScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Finds duplicate images by file content. Videos are ignored.")
                }

                if viewModel.isDedupScanInProgress {
                    ProgressView(value: viewModel.dedupProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text(viewModel.dedupMessage)
                        .font(.caption)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Maintenance", systemImage: "wrench.and.screwdriver")
        }
        .padding(.horizontal)
    }

    private func syncFromState() {
        includePhotos = viewModel.state.includePhotos
        includeVideos = viewModel.state.includeVideos
        includeLivePhotosAsVideo = viewModel.state.includeLivePhotosAsVideo
        showThumbnail = viewModel.state.showThumbnail
        backupFolderLayout = viewModel.state.backupFolderLayout
        backupFileNaming = viewModel.state.backupFileNaming
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

    private func pushOutputSettings() {
        viewModel.applyOutputSettingsFromUI(
            folderLayout: backupFolderLayout,
            fileNaming: backupFileNaming
        )
        viewModel.refreshMissingCounts()
    }
}

struct BackupSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        BackupSettingsView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
