import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @State private var confirmClearLog = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    summaryRows
                } header: {
                    Text("Overview")
                }

                Section {
                    if viewModel.activityLogEntries.isEmpty {
                        Text("No activity yet. Run a backup or scan for duplicates to build history.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.activityLogEntries) { entry in
                            ActivityLogRow(entry: entry)
                        }
                    }
                } header: {
                    HStack {
                        Text("Activity log")
                        Spacer()
                        if !viewModel.activityLogEntries.isEmpty {
                            Button("Clear") {
                                confirmClearLog = true
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .onAppear {
                viewModel.refreshActivityLog()
            }
            .confirmationDialog(
                "Clear all history entries?",
                isPresented: $confirmClearLog,
                titleVisibility: .visible
            ) {
                Button("Clear log", role: .destructive) {
                    viewModel.clearActivityLog()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the activity list. Your backup folder and settings are not changed.")
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder private var summaryRows: some View {
        HStack {
            Text("Total backup size")
            Spacer()
            Text(
                ByteCountFormatter.string(
                    fromByteCount: viewModel.state.totalBackupSize,
                    countStyle: .file
                )
            )
            .foregroundColor(.secondary)
        }
        if let last = viewModel.state.lastBackupDate {
            HStack {
                Text("Last backup")
                Spacer()
                Text(last, format: .dateTime.day().month().year().hour().minute())
                    .foregroundColor(.secondary)
            }
        } else {
            HStack {
                Text("Last backup")
                Spacer()
                Text("—")
                    .foregroundColor(.secondary)
            }
        }
        HStack {
            Text("Completed backups (logged)")
            Spacer()
            Text("\(viewModel.completedBackupLogCount)")
                .foregroundColor(.secondary)
        }
        HStack {
            Text("Log entries")
            Spacer()
            Text("\(viewModel.activityLogEntries.count)")
                .foregroundColor(.secondary)
        }
    }
}

private struct ActivityLogRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: entry.kind.symbolName)
                    .foregroundColor(.secondary)
                    .frame(width: 22, alignment: .center)
                Text(entry.summary)
                    .font(.subheadline)
            }
            Text(entry.date, format: .dateTime.month().day().hour().minute())
                .font(.caption2)
                .foregroundColor(.secondary)
            if let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private extension ActivityLogKind {
    var symbolName: String {
        switch self {
        case .backupCompleted, .shortcutBackupCompleted:
            return "checkmark.circle.fill"
        case .backupCanceled, .dedupScanCanceled:
            return "xmark.circle"
        case .backupFailed, .folderClearFailed, .dedupScanFailed, .dedupDeleteFailed:
            return "exclamationmark.triangle.fill"
        case .folderChanged:
            return "folder.badge.plus"
        case .folderCleared:
            return "trash.circle"
        case .dedupNoDuplicates:
            return "photo.on.rectangle.angled"
        case .dedupDuplicatesFound:
            return "doc.on.doc"
        case .dedupDeleted:
            return "minus.circle.fill"
        }
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
