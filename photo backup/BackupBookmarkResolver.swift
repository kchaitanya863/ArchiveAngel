import Foundation

extension Notification.Name {
    /// Posted when `AppPersistentState` is updated on disk outside the view model (e.g. Shortcuts backup).
    static let archiveAngelPersistentStateDidChange = Notification.Name("ArchiveAngelPersistentStateDidChange")
}

enum BackupBookmarkResolver {
    /// Resolves the security-scoped folder URL from `state.backupFolderBookmark`, clearing invalid or stale bookmarks and persisting.
    static func resolvedBackupFolderURL(state: inout AppPersistentState, store: AppStateStore) -> URL? {
        guard let data = state.backupFolderBookmark else { return nil }
        var stale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        else {
            state.backupFolderBookmark = nil
            store.save(state)
            return nil
        }
        if stale {
            state.backupFolderBookmark = nil
            store.save(state)
            return nil
        }
        return url
    }
}
