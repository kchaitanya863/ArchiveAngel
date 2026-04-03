import Photos
import SwiftUI

/// Advanced backup options: media filters, export layout, and maintenance tools.
struct BackupSettingsView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @Environment(\.inSidebar) private var inSidebar

    @State private var includePhotos = true
    @State private var includeVideos = true
    @State private var includeLivePhotosAsVideo = true
    @State private var showThumbnail = true
    @State private var backupFolderLayout = BackupFolderLayout.flat
    @State private var backupFileNaming = BackupFileNaming.identifierAndOriginal
    @State private var backupIncrementalEnabled = false
    @State private var selectedAlbumIds = Set<String>()
    @State private var pickableAlbums: [PickableAlbum] = []
    @State private var showAlbumScopePicker = false

    var body: some View {
        Group {
            if inSidebar {
                settingsContent
            } else {
                NavigationView {
                    settingsContent
                }
                .navigationViewStyle(.stack)
            }
        }
        .onAppear {
            syncFromState()
            reloadPickableAlbums()
        }
        .onChange(of: viewModel.state) { _ in syncFromState() }
        .onChange(of: includePhotos) { _ in pushSettings() }
        .onChange(of: includeVideos) { _ in pushSettings() }
        .onChange(of: includeLivePhotosAsVideo) { _ in pushSettings() }
        .onChange(of: showThumbnail) { _ in pushSettings() }
        .onChange(of: backupFolderLayout) { _ in pushOutputSettings() }
        .onChange(of: backupFileNaming) { _ in pushOutputSettings() }
        .onChange(of: backupIncrementalEnabled) { _ in pushBackupScope() }
        .sheet(isPresented: $showAlbumScopePicker) {
            AlbumScopePickerView(
                selectedIds: $selectedAlbumIds,
                albums: pickableAlbums,
                onApply: pushBackupScope
            )
        }
        .onChange(of: showAlbumScopePicker) { opened in
            if opened, pickableAlbums.isEmpty {
                reloadPickableAlbums()
            }
        }
    }

    // MARK: - Inner content (shared between sidebar and tab-bar contexts)

    private var settingsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                backupSettingsSection
                backupScopeSection
                outputLayoutSection
                aboutSection
                maintenanceSection
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
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

    private var backupScopeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Only new or changed since last backup", isOn: $backupIncrementalEnabled)
                    .accessibilityHint(
                        "Uses your library and the last successful backup time, not the current folder. Only photos and videos added or edited after that time are exported—so you can point at a new drive and avoid copying your whole library again."
                    )
                Text(
                    "Based on your photo library and the time of the last successful backup—not on whether files already exist in the folder you pick. New or edited items since then are copied; older items are skipped even if the destination is empty (for example a new USB drive or NAS). Turn off to fill a fresh folder with everything in scope."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 4)

                Text("Album scope")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(
                    "Leave no albums selected to use the entire library. Tap the button below to search, filter, and pick albums or smart albums in a full-screen list—easier when you have many."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(albumScopeStatusLine)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(albumScopeStatusAccessibility)

                Button {
                    showAlbumScopePicker = true
                } label: {
                    Label("Choose albums…", systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(albumAccessLikelyDenied)
                .accessibilityHint("Opens a searchable list of albums and smart albums.")

                HStack {
                    Button("Clear album selection") {
                        selectedAlbumIds.removeAll()
                        pushBackupScope()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedAlbumIds.isEmpty)
                    Spacer()
                    Button {
                        reloadPickableAlbums()
                    } label: {
                        Label("Refresh list", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Reloads albums from your photo library.")
                }

                if pickableAlbums.isEmpty {
                    Text(albumLoadingOrAccessLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Scope", systemImage: "rectangle.stack")
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

    private var aboutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Archive Angel helps you export your Photos library to a folder you choose, with optional duplicate photo cleanup after review.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "https://forms.gle/FbM4bJ3dz5PpiFA19")!) {
                    Label("Share feedback", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Link(destination: URL(string: "https://github.com/kchaitanya863/ArchiveAngel/issues")!) {
                    Label("Create an issue", systemImage: "exclamationmark.bubble")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Link(destination: URL(string: "https://github.com/kchaitanya863/ArchiveAngel")!) {
                    Label("Contribute to open source", systemImage: "hammer")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Link(destination: URL(string: "https://github.com/kchaitanya863/ArchiveAngel")!) {
                    Label("View source code", systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("About", systemImage: "info.circle")
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
        backupIncrementalEnabled = viewModel.state.backupIncrementalEnabled
        selectedAlbumIds = Set(viewModel.state.backupAlbumCollectionLocalIdentifiers)
    }

    private func pushBackupScope() {
        viewModel.applyBackupScopeFromUI(
            albumCollectionLocalIdentifiers: Array(selectedAlbumIds),
            incrementalEnabled: backupIncrementalEnabled
        )
        viewModel.refreshMissingCounts()
    }

    private func reloadPickableAlbums() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { pickableAlbums = [] }
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let rows = BackupAlbumCatalog.loadPickableAlbums()
                DispatchQueue.main.async {
                    pickableAlbums = rows
                }
            }
        }
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

    private var albumScopeStatusLine: String {
        if selectedAlbumIds.isEmpty {
            return "Scope: entire library"
        }
        let n = selectedAlbumIds.count
        return "Scope: \(n) album\(n == 1 ? "" : "s")"
    }

    private var albumScopeStatusAccessibility: String {
        if selectedAlbumIds.isEmpty {
            return "Backup scope is the entire photo library."
        }
        return "\(selectedAlbumIds.count) albums selected for backup scope."
    }

    /// After a denied auth callback, `pickableAlbums` stays empty; avoid enabling the picker misleadingly.
    private var albumAccessLikelyDenied: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .denied || s == .restricted
    }

    private var albumLoadingOrAccessLine: String {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch s {
        case .denied, .restricted:
            return "Photo access is off. Enable it in Settings to load albums."
        case .notDetermined:
            return "Loading albums… If this stays empty, grant photo access when prompted."
        default:
            return "Loading albums…"
        }
    }
}

struct BackupSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        BackupSettingsView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
