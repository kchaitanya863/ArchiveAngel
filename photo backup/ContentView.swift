import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                exportIndexStatusSection
                libraryStatsSection
                diskSpaceSection
                settingsHintRow
                backupMetadataSection
                primaryBackupButton
                backupDestinationSection
                backupProgressSection
            }
            .padding(.vertical, 24)
            // On iPad (regular size class), cap the content width and center it so
            // the layout uses horizontal space sensibly instead of stretching wall-to-wall.
            .frame(maxWidth: horizontalSizeClass == .regular ? 680 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var heroSection: some View {
        let iconSize: CGFloat = horizontalSizeClass == .regular ? 120 : 200
        Image("AppHomeIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
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

    @ViewBuilder private var exportIndexStatusSection: some View {
        if viewModel.isExportIndexReindexing || !viewModel.exportIndexStatusDetail.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
                Text(viewModel.exportIndexStatusDetail.isEmpty ? "Indexing backup folder…" : viewModel.exportIndexStatusDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.exportIndexStatusDetail)
        }
    }

    @ViewBuilder private var libraryStatsSection: some View {
        Text("Photos: \(viewModel.totalPhotosCount), videos: \(viewModel.totalVideosCount)")
            .font(.subheadline)
            .accessibilityElement(children: .combine)

        HStack(alignment: .center, spacing: 10) {
            if viewModel.isMissingCountsRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning library for missing items…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Scanning library for items not yet in the backup folder")
            } else {
                Text(missingCountsLabel)
                    .font(.subheadline)
                    .accessibilityLabel(missingCountsAccessibilityLabel)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.refreshMissingCounts()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isMissingCountsRefreshing)
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
        if viewModel.isBackupInProgress {
            HStack(alignment: .top, spacing: 12) {
                if viewModel.state.showThumbnail, let thumbnail = viewModel.currentThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                        .accessibilityLabel("Current item thumbnail")
                }

                if let p = viewModel.backupLiveProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.headline)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(4)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(backupProgressIOLine(p))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)

                        Text(backupProgressCountsLine(p))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        Text(backupProgressAssetLine(p))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(p.accessibilitySummary)
                } else {
                    Text("Preparing backup…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)

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

    private func backupProgressIOLine(_ p: BackupLiveProgress) -> String {
        "I/O: \(p.sessionBytesFormatted) · \(p.averageThroughputFormatted) · ETA ~\(p.etaFormatted) · elapsed \(p.elapsedFormatted)"
    }

    private func backupProgressCountsLine(_ p: BackupLiveProgress) -> String {
        let rate = p.stepsPerSecond
        return String(
            format: "Items: %d written · %d skipped · %d/%d visited · %.2f steps/s",
            p.filesWritten,
            p.filesSkipped,
            p.processedStep,
            p.totalEligible,
            rate
        )
    }

    private func backupProgressAssetLine(_ p: BackupLiveProgress) -> String {
        if p.isSkipping {
            return "Asset: \(p.mediaLabel)"
        }
        return "Asset: \(p.mediaLabel) · last write \(p.lastWriteFormatted)"
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
