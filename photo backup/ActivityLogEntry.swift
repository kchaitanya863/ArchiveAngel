import Foundation

enum ActivityLogKind: String, Codable {
    case backupCompleted
    case backupCanceled
    case backupFailed
    case shortcutBackupCompleted
    case folderChanged
    case folderCleared
    case folderClearFailed
    case dedupNoDuplicates
    case dedupDuplicatesFound
    case dedupScanCanceled
    case dedupScanFailed
    case dedupDeleted
    case dedupDeleteFailed
}

struct ActivityLogEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var kind: ActivityLogKind
    /// Primary line shown in the list.
    var summary: String
    /// Optional extra detail (e.g. error text).
    var detail: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: ActivityLogKind,
        summary: String,
        detail: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }
}

/// Filter chips / menu for the History screen.
enum ActivityLogListFilter: String, CaseIterable, Identifiable {
    case all
    case backups
    case folder
    case duplicates
    case issues

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .all: return "All activity"
        case .backups: return "Backups"
        case .folder: return "Folder"
        case .duplicates: return "Duplicates"
        case .issues: return "Issues & cancels"
        }
    }
}

extension ActivityLogKind {
    func matches(_ filter: ActivityLogListFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .backups:
            switch self {
            case .backupCompleted, .shortcutBackupCompleted, .backupCanceled, .backupFailed:
                return true
            default:
                return false
            }
        case .folder:
            switch self {
            case .folderChanged, .folderCleared, .folderClearFailed:
                return true
            default:
                return false
            }
        case .duplicates:
            switch self {
            case .dedupNoDuplicates, .dedupDuplicatesFound, .dedupScanCanceled, .dedupScanFailed, .dedupDeleted,
                 .dedupDeleteFailed:
                return true
            default:
                return false
            }
        case .issues:
            switch self {
            case .backupFailed, .backupCanceled, .folderClearFailed, .dedupScanFailed, .dedupDeleteFailed,
                 .dedupScanCanceled:
                return true
            default:
                return false
            }
        }
    }
}

/// Plain-text export for sharing or diagnostics (newest entries first).
enum ActivityLogExport {
    static func plainTextDocument(entries: [ActivityLogEntry]) -> String {
        let sorted = entries.sorted { $0.date > $1.date }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        df.locale = Locale.autoupdatingCurrent
        var lines: [String] = ["Archive Angel — activity log", "Generated \(df.string(from: Date()))", ""]
        for entry in sorted {
            lines.append("[\(df.string(from: entry.date))] \(entry.kind.rawValue)")
            lines.append(entry.summary)
            if let detail = entry.detail, !detail.isEmpty {
                lines.append(detail)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

extension Notification.Name {
    static let archiveAngelActivityLogDidChange = Notification.Name("ArchiveAngelActivityLogDidChange")
}
