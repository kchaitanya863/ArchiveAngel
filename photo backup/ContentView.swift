import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel

    var body: some View {
        mainScrollView
            .sheet(isPresented: $viewModel.showDocumentPicker) {
                DocumentPicker { url in
                    viewModel.userPickedBackupFolder(url)
                }
            }
            .onAppear(perform: handleAppear)
    }

    // MARK: - Main stack (split for Swift compiler / previews)

    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroSection
                chooseBackupFolderCallout
                libraryStatsSection
                settingsHintRow
                backupMetadataSection
                primaryBackupButton
                backupDestinationSection
                backupProgressSection
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

    private var settingsHintRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "gearshape")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("Filters, export layout, duplicate scan, and clearing the folder are in the Settings tab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filters, export layout, duplicate scan, and clearing the folder are in the Settings tab.")
    }

    private var missingCountsLabel: String {
        "Missing — photos: \(viewModel.totalMissingPhotosCount), videos: \(viewModel.totalMissingVideosCount)"
    }

    private var missingCountsAccessibilityLabel: String {
        "Missing from backup: \(viewModel.totalMissingPhotosCount) photos, \(viewModel.totalMissingVideosCount) videos"
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

    private func handleAppear() {
        viewModel.refreshMediaCounts()
        viewModel.refreshMissingCounts()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
