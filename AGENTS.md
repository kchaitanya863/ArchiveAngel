# Agent instructions — Archive Angel

Use this file when editing or reviewing this repository in an automated or assisted workflow.

## Product

- **Platform:** iOS and iPadOS only. The app target is **Archive Angel**; the Swift module is **`photo_backup`** (`PRODUCT_MODULE_NAME`). Do not claim macOS support without adding a real macOS target and replacing UIKit-only surfaces (e.g. `UIDocumentPicker`, `UIImage`).
- **Purpose:** Export Photos library assets to a user-picked folder; optional duplicate **photo** removal after scan + user confirmation.

## Architecture (do not fight it)

- **`ArchiveAngelViewModel`** (`@MainActor`) holds UI state, talks to `BackupManager` / `DeduplicationManager`, and persists via **`AppStateStore`**.
- **On-disk state:** `Application Support/ArchiveAngel/app_state.json` via `AppPersistentState`. Legacy `UserDefaults` keys are migrated once by `AppStateStore`.
- **Tabs:** **`ArchiveAngelRootView`** hosts Backup (`ContentView`), History (`HistoryView`), and Settings (`BackupSettingsView`: media filters, output layout, clear folder, duplicate scan). Alerts and folder/duplicate confirmation dialogs are attached on the root so they appear regardless of the selected tab.
- **Activity log:** `Application Support/ArchiveAngel/activity_log.json` via **`ActivityLogStore`** (newest-first, capped ~400 entries). **`HistoryView`** tab; **`ArchiveAngelViewModel.recordActivity`** (private) and Shortcuts intent append events. **`archiveAngelActivityLogDidChange`** refreshes the list when the log changes off the main flow.
- **Backup folder:** Stored as **bookmark `Data`** in `AppPersistentState`. On iOS, use **empty bookmark options** `[]` for create/resolve — **not** `.withSecurityScope` on `URL` (unavailable on iOS in Swift). Always use `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` around file access on the resolved URL where appropriate (`BackupManager` wraps backup/clear).
- **Naming & layout:** `BackupFolderLayout` / `BackupFileNaming` in **`BackupOutputSettings.swift`** (persisted on `AppPersistentState`); **`BackupOutputPathMath`** is pure UTC-based path math; **`BackupNaming.backupFileURL`** composes subfolders + basename and **`isAssetBackedUp`** checks the current pattern plus **legacy flat** `id_original` and concatenated names.
- **Scope & incremental:** **`BackupScope`** / **`BackupScopeRules`** gate which assets are considered. Incremental mode uses **`lastBackupDate`** as a **library** watermark (creation/modification vs that time), not “missing from the current folder,” so a new destination does not re-export the whole library; **`lastBackupDate`** updates only when a backup **completes without cancel**.
- **Dedup:** **`DeduplicationManager`** scans **images only**; flow is scan → confirm dialog → delete. Do not silently delete.
- **Shortcuts:** **`RunBackupToLastFolderIntent`** (`RunBackupAppIntents.swift`, iOS 16+) uses **`BackupBookmarkResolver`** + **`BackupManager`** and **`AppStateStore`**. It sets **`openAppWhenRun = true`** so the backup runs in the foreground. On success it saves state and posts **`Notification.Name.archiveAngelPersistentStateDidChange`** so **`ArchiveAngelViewModel`** reloads from disk.

## Constraints for changes

- Prefer **small, task-scoped diffs**. Reuse existing patterns (bindings through the view model, `Result` completions, main-thread UI updates).
- New Swift files must be added to **`ArchiveAngel.xcodeproj/project.pbxproj`** (Sources + group).
- **Tests:** Pure logic belongs in testable helpers (`BackupProgressMath`, `BackupNaming.sanitizeFilename`, `BackupOutputPathMath`, `CryptoHelpers`, `AppPersistentState` / `AppStateStore`). Run **`photo backupTests`** after non-trivial changes.
- **Info.plist:** Merged from `photo-backup-Info.plist` and generated keys; keep `NSPhotoLibraryUsageDescription` accurate if behavior changes.
- **App Intents:** New intents must be registered via `AppShortcutsProvider` (or equivalent) and compile with the **Archive Angel** target so `appintentsmetadataprocessor` runs. Keep intent titles/phrases user-facing and accurate.

## Build / test commands

```bash
xcodebuild -scheme "Archive Angel" -destination 'generic/platform=iOS' build
xcodebuild test -scheme "Archive Angel" -destination 'platform=iOS Simulator,name=<Simulator Name>' -only-testing:'photo backupTests'
```

## Git hygiene

- Do not commit **DerivedData**, **`build/`** (local derived data), **`.DS_Store`**, or **`xcuserdata`** — see `.gitignore`.
