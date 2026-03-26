# Agent instructions — Archive Angel

Use this file when editing or reviewing this repository in an automated or assisted workflow.

## Product

- **Platform:** iOS and iPadOS only. The app target is **Archive Angel**; the Swift module is **`photo_backup`** (`PRODUCT_MODULE_NAME`). Do not claim macOS support without adding a real macOS target and replacing UIKit-only surfaces (e.g. `UIDocumentPicker`, `UIImage`).
- **Purpose:** Export Photos library assets to a user-picked folder; optional duplicate **photo** removal after scan + user confirmation.

## Architecture (do not fight it)

- **`ArchiveAngelViewModel`** (`@MainActor`) holds UI state, talks to `BackupManager` / `DeduplicationManager`, and persists via **`AppStateStore`**.
- **On-disk state:** `Application Support/ArchiveAngel/app_state.json` via `AppPersistentState`. Legacy `UserDefaults` keys are migrated once by `AppStateStore`.
- **Backup folder:** Stored as **bookmark `Data`** in `AppPersistentState`. On iOS, use **empty bookmark options** `[]` for create/resolve — **not** `.withSecurityScope` on `URL` (unavailable on iOS in Swift). Always use `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` around file access on the resolved URL where appropriate (`BackupManager` wraps backup/clear).
- **Naming:** `BackupNaming` builds paths from `PHAssetResource` filenames plus a sanitized id prefix; **`BackupNaming.isAssetBackedUp`** also checks a **legacy** filename pattern for older backups.
- **Dedup:** **`DeduplicationManager`** scans **images only**; flow is scan → confirm dialog → delete. Do not silently delete.

## Constraints for changes

- Prefer **small, task-scoped diffs**. Reuse existing patterns (bindings through the view model, `Result` completions, main-thread UI updates).
- New Swift files must be added to **`ArchiveAngel.xcodeproj/project.pbxproj`** (Sources + group).
- **Tests:** Pure logic belongs in testable helpers (`BackupProgressMath`, `BackupNaming.sanitizeFilename`, `CryptoHelpers`, `AppPersistentState` / `AppStateStore`). Run **`photo backupTests`** after non-trivial changes.
- **Info.plist:** Merged from `photo-backup-Info.plist` and generated keys; keep `NSPhotoLibraryUsageDescription` accurate if behavior changes.

## Build / test commands

```bash
xcodebuild -scheme "Archive Angel" -destination 'generic/platform=iOS' build
xcodebuild test -scheme "Archive Angel" -destination 'platform=iOS Simulator,name=<Simulator Name>' -only-testing:'photo backupTests'
```

## Git hygiene

- Do not commit **DerivedData**, **`build/`** (local derived data), **`.DS_Store`**, or **`xcuserdata`** — see `.gitignore`.
