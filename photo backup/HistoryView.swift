import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel

    @State private var searchText = ""
    @State private var logFilter: ActivityLogListFilter = .all
    @State private var confirmClearLog = false
    @State private var detailEntry: ActivityLogEntry?
    @State private var showCopiedFeedback = false

    var body: some View {
        NavigationView {
            List {
                overviewSection

                if filteredEntries.isEmpty {
                    Section {
                        emptyStateContent
                    }
                } else {
                    if !filterSummaryLine.isEmpty {
                        Section {
                            Text(filterSummaryLine)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }
                    ForEach(daySections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                Button {
                                    detailEntry = entry
                                } label: {
                                    ActivityLogRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Show full details and copy options.")
                            }
                        } header: {
                            Text(section.title)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: Text("Search summary or details"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(ActivityLogListFilter.allCases) { f in
                            Button {
                                logFilter = f
                            } label: {
                                if logFilter == f {
                                    Label(f.menuTitle, systemImage: "checkmark")
                                } else {
                                    Text(f.menuTitle)
                                }
                            }
                        }
                    } label: {
                        Label(logFilter.menuTitle, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Activity filter, \(logFilter.menuTitle)")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareFilteredLog()
                        } label: {
                            Label("Share log…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(filteredEntries.isEmpty)
                        Button {
                            copyFilteredLog()
                        } label: {
                            Label("Copy log to clipboard", systemImage: "doc.on.doc")
                        }
                        .disabled(filteredEntries.isEmpty)
                        Divider()
                        Button(role: .destructive) {
                            confirmClearLog = true
                        } label: {
                            Label("Clear all activity", systemImage: "trash")
                        }
                        .disabled(viewModel.activityLogEntries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Log actions")
                }
            }
            .refreshable {
                viewModel.refreshActivityLog()
            }
            .onAppear {
                viewModel.refreshActivityLog()
            }
            .confirmationDialog(
                "Clear all activity entries?",
                isPresented: $confirmClearLog,
                titleVisibility: .visible
            ) {
                Button("Clear log", role: .destructive) {
                    viewModel.clearActivityLog()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes saved history only. Your backup folder, bookmarks, and settings stay as they are.")
            }
            .sheet(item: $detailEntry) { entry in
                ActivityLogDetailSheet(entry: entry) {
                    detailEntry = nil
                }
            }
            .alert("Copied to clipboard", isPresented: $showCopiedFeedback) {
                Button("OK", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }

    private var allEntries: [ActivityLogEntry] {
        viewModel.activityLogEntries
    }

    private var filteredEntries: [ActivityLogEntry] {
        let byKind = allEntries.filter { $0.kind.matches(logFilter) }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return byKind }
        let needle = q.lowercased()
        return byKind.filter { entry in
            entry.summary.lowercased().contains(needle)
                || (entry.detail?.lowercased().contains(needle) ?? false)
        }
    }

    private var filterSummaryLine: String {
        guard !allEntries.isEmpty else { return "" }
        if logFilter == .all, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        return "Showing \(filteredEntries.count) of \(allEntries.count) entries"
    }

    private var daySections: [HistoryDaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { cal.startOfDay(for: $0.date) }
        let days = grouped.keys.sorted(by: >)
        return days.map { day in
            HistoryDaySection(
                id: day,
                title: sectionTitle(for: day),
                entries: grouped[day]!.sorted { $0.date > $1.date }
            )
        }
    }

    private func sectionTitle(for startOfDay: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(startOfDay) { return "Today" }
        if cal.isDateInYesterday(startOfDay) { return "Yesterday" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = false
        f.locale = Locale.autoupdatingCurrent
        return f.string(from: startOfDay)
    }

    @ViewBuilder private var emptyStateContent: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(emptyStateTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(emptyStateSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private var emptyStateTitle: String {
        if allEntries.isEmpty { return "No activity yet" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        return "Nothing in this filter"
    }

    private var emptyStateSubtitle: String {
        if allEntries.isEmpty {
            return "Run a backup, change your backup folder, or scan for duplicates. Entries appear here with the time and any extra detail."
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try different words, clear the search field, or set the filter to “All activity”."
        }
        return "Choose “All activity” or another filter to see more entries."
    }

    @ViewBuilder private var overviewSection: some View {
        Section {
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
                Text("Log entries stored")
                Spacer()
                Text("\(allEntries.count)")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Overview")
        } footer: {
            Text("The log keeps roughly the most recent 400 events. Pull down to refresh after Shortcuts or another device changes state.")
                .font(.caption)
        }
    }

    private func shareFilteredLog() {
        let text = ActivityLogExport.plainTextDocument(entries: filteredEntries)
        ActivityLogPresenter.presentShareSheet(text: text)
    }

    private func copyFilteredLog() {
        UIPasteboard.general.string = ActivityLogExport.plainTextDocument(entries: filteredEntries)
        showCopiedFeedback = true
    }
}

// MARK: - Grouping model

private struct HistoryDaySection: Identifiable {
    let id: Date
    let title: String
    let entries: [ActivityLogEntry]
}

// MARK: - Row

private struct ActivityLogRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.symbolName)
                .font(.body)
                .foregroundColor(entry.kind.rowIconColor)
                .frame(width: 26, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelForEntry)
    }

    private var accessibilityLabelForEntry: String {
        var parts = [entry.summary, entry.date.formatted(date: .abbreviated, time: .shortened)]
        if let d = entry.detail, !d.isEmpty {
            parts.append(d)
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Detail sheet

private struct ActivityLogDetailSheet: View {
    let entry: ActivityLogEntry
    let onDismiss: () -> Void

    @State private var showCopied = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: entry.kind.symbolName)
                            .font(.title2)
                            .foregroundColor(entry.kind.rowIconColor)
                        Text(entry.kind.displayTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    Text(entry.summary)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(entry.date.formatted(date: .complete, time: .standard))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let detail = entry.detail, !detail.isEmpty {
                        Divider()
                        Text(detail)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("No additional detail for this entry.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        UIPasteboard.general.string = detailClipboardText
                        showCopied = true
                    }
                }
            }
            .alert("Copied", isPresented: $showCopied) {
                Button("OK", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }

    private var detailClipboardText: String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .medium
        var lines = [
            entry.kind.rawValue,
            df.string(from: entry.date),
            entry.summary,
        ]
        if let d = entry.detail, !d.isEmpty {
            lines.append(d)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Kind presentation

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

    var rowIconColor: Color {
        switch self {
        case .backupCompleted, .shortcutBackupCompleted, .dedupDeleted, .dedupNoDuplicates:
            return Color.green
        case .folderChanged, .folderCleared, .dedupDuplicatesFound:
            return Color.blue
        case .backupFailed, .folderClearFailed, .dedupScanFailed, .dedupDeleteFailed:
            return Color.orange
        case .backupCanceled, .dedupScanCanceled:
            return Color.gray
        }
    }

    var displayTitle: String {
        switch self {
        case .backupCompleted: return "Backup"
        case .backupCanceled: return "Backup canceled"
        case .backupFailed: return "Backup failed"
        case .shortcutBackupCompleted: return "Shortcuts backup"
        case .folderChanged: return "Folder"
        case .folderCleared: return "Folder cleared"
        case .folderClearFailed: return "Folder error"
        case .dedupNoDuplicates: return "Duplicates"
        case .dedupDuplicatesFound: return "Duplicates"
        case .dedupScanCanceled: return "Duplicate scan"
        case .dedupScanFailed: return "Duplicate scan"
        case .dedupDeleted: return "Duplicates removed"
        case .dedupDeleteFailed: return "Duplicate delete"
        }
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
