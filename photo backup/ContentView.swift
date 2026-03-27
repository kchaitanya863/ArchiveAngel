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
                diskSpaceSection
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

        if let summary = backupScopeSummary {
            Text(summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .accessibilityLabel(backupScopeAccessibilityLabel)
        }
    }

    private var backupScopeSummary: String? {
        let albums = viewModel.state.backupAlbumCollectionLocalIdentifiers.count
        let incremental = viewModel.state.backupIncrementalEnabled
        if albums == 0, !incremental { return nil }
        var parts: [String] = []
        if albums > 0 {
            parts.append("\(albums) album\(albums == 1 ? "" : "s")")
        } else {
            parts.append("Entire library")
        }
        parts.append(incremental ? "incremental on" : "incremental off")
        return parts.joined(separator: " · ")
    }

    private var backupScopeAccessibilityLabel: String {
        let albums = viewModel.state.backupAlbumCollectionLocalIdentifiers.count
        let incremental = viewModel.state.backupIncrementalEnabled
        let scopeText =
            albums > 0
            ? "Backup scope is limited to \(albums) selected albums."
            : "Backup scope is the entire photo library."
        let incText =
            incremental
            ? "Incremental backup is on; only items added or edited in the library after the last successful backup are exported, even if the backup folder is new or empty."
            : "Incremental backup is off."
        return "\(scopeText) \(incText)"
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

    @ViewBuilder private var diskSpaceSection: some View {
        if viewModel.state.backupFolderBookmark != nil {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.diskSpaceNeededForMissingBytes > 0 {
                    Text(diskSpaceNeededLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .accessibilityLabel(diskSpaceNeededAccessibilityLabel)
                }
                Text(diskSpaceFreeLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(diskSpaceFreeAccessibilityLabel)
                if let warning = diskSpaceWarningText {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    private var diskSpaceNeededLabel: String {
        let formatted = ByteCountFormatter.string(
            fromByteCount: viewModel.diskSpaceNeededForMissingBytes,
            countStyle: .file
        )
        return "Rough space for new items: \(formatted) (approximate)"
    }

    private var diskSpaceNeededAccessibilityLabel: String {
        let formatted = ByteCountFormatter.string(
            fromByteCount: viewModel.diskSpaceNeededForMissingBytes,
            countStyle: .file
        )
        return "Rough space needed for items not yet backed up: about \(formatted). This is approximate."
    }

    private var diskSpaceFreeLabel: String {
        if let free = viewModel.diskSpaceDestinationFreeBytes {
            let formatted = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            return "Destination free space: \(formatted)"
        }
        return "Destination free space: unavailable"
    }

    private var diskSpaceFreeAccessibilityLabel: String {
        if let free = viewModel.diskSpaceDestinationFreeBytes {
            let formatted = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            return "Free space on the backup destination: about \(formatted)"
        }
        return "Free space on the backup destination could not be read."
    }

    private var diskSpaceWarningText: String? {
        switch viewModel.diskSpaceAssessment {
        case .tightRemaining(let headroom):
            let hf = ByteCountFormatter.string(fromByteCount: headroom, countStyle: .file)
            return "Low space: only about \(hf) would remain after the estimate. Consider freeing room or using another folder."
        case .insufficient(let shortBy):
            let sf = ByteCountFormatter.string(fromByteCount: shortBy, countStyle: .file)
            return "Not enough free space for the rough estimate (short by about \(sf)). You can still try to back up."
        case .unknownFreeSpace:
            if viewModel.diskSpaceNeededForMissingBytes > 0 {
                return "Could not read free space for this location; the estimate may not match what the Files provider reports."
            }
            return nil
        default:
            return nil
        }
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
