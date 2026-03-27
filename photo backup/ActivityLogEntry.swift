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

extension Notification.Name {
    static let archiveAngelActivityLogDidChange = Notification.Name("ArchiveAngelActivityLogDidChange")
}
