# Archive Angel

SwiftUI app for **iPhone and iPad** that exports your Photos library to a folder you pick (including iCloud-backed assets when the system downloads them), shows progress, and can **find duplicate photos** by content hash before you confirm deletion. **macOS is not a supported target** in the current codebase (UIKit document picker and iOS app shell).

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/archiveangel)

## Features

- **Backup** — Copies images and/or videos into a user-selected directory; skips files that already exist; optional Live Photo companion `.mov`; preserves creation/modification dates on exported files.
- **Progress** — Linear progress by number of library items that match your filters; optional thumbnail while copying; cancel anytime.
- **Folder bookmark** — The backup location is stored as a bookmark in on-disk app state so it can be restored after relaunch (you may need to re-pick the folder if the bookmark goes stale).
- **State on disk** — Preferences and backup stats live in Application Support as JSON (`ArchiveAngel/app_state.json`), with a one-time migration from legacy `UserDefaults` keys.
- **Clear folder** — Removes **contents** of the backup folder only (keeps the folder node and security-scoped access pattern).
- **Duplicate photos** — Scans **images only** (SHA-256 of image data); videos are not scanned. After a scan, you confirm before anything is deleted from the library.
- **Siri & Shortcuts (iOS 16+)** — App Intent **“Run backup to last folder”** opens the app and runs the same backup as the in-app button, using your saved folder bookmark and settings. Find it under the app in Shortcuts, or say e.g. “Run backup in Archive Angel” (phrase depends on your app display name).
- **History tab** — Overview of total backup size, last backup time, and counts from the log; chronological **activity log** (backups, folder changes, clears, duplicate scans/deletes, Shortcuts runs). Stored under `ArchiveAngel/activity_log.json` (newest first, capped). You can clear the log without touching files or settings.

## Requirements

- **iOS / iPadOS 15.0+** to run the app; **iOS / iPadOS 16+** for Shortcuts / App Intents discovery.
- **Xcode 15+** (project last built with Xcode 15+ toolchains)
- **Swift 5**

## Project layout

| Area | Location |
|------|----------|
| UI | `photo backup/ArchiveAngelRootView.swift` (tabs), `ContentView.swift`, `HistoryView.swift` |
| View model | `photo backup/ArchiveAngelViewModel.swift` |
| Backup / clear folder | `photo backup/BackupManager.swift` |
| Dedup scan + delete | `photo backup/DeduplicationManager.swift` |
| Filenames & progress helpers | `photo backup/BackupNaming.swift`, `BackupProgressMath` |
| Persistent JSON state | `photo backup/AppPersistentState.swift`, `AppStateStore.swift` |
| Activity log | `photo backup/ActivityLogEntry.swift`, `ActivityLogStore.swift` |
| Document folder picker | `photo backup/DocumentPicker.swift` |
| Shortcuts (App Intents) | `photo backup/RunBackupAppIntents.swift`, `BackupBookmarkResolver.swift` |
| Unit tests | `photo backupTests/ArchiveAngelCoreTests.swift` |

Swift **module name** for the app target is `photo_backup` (see `PRODUCT_MODULE_NAME` in Xcode).

## Build and run

1. Clone the repo: `git clone https://github.com/kchaitanya863/ArchiveAngel/`
2. Open `ArchiveAngel.xcodeproj` in Xcode.
3. Select the **Archive Angel** scheme and an iPhone or iPad simulator or device.
4. Run (**⌘R**).

### Unit tests

In Xcode: **Product → Test** for the `photo backupTests` target, or:

```bash
xcodebuild test -scheme "Archive Angel" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:'photo backupTests'
```

Adjust the simulator name to one installed on your Mac (`xcodebuild -showdestinations`).

## Usage (short)

1. **Select backup folder** — Grants access to a directory (often iCloud Drive or “On My iPhone”).
2. **Back up library** — Exports according to toggles (photos, videos, Live Photo as video, thumbnail).
3. **Clear folder contents** — Confirms, then deletes files inside that folder only.
4. **Scan for duplicate photos** — When finished, review the confirmation; **Delete** removes duplicate library assets (keeps one copy per identical image).
5. **Shortcuts** — After you have chosen a backup folder once in the app, add **Run backup to last folder** from the Shortcuts app (App Library → Archive Angel) or Siri. The shortcut requests photo access if needed and shows a summary when the run finishes.

## Privacy

Photo library usage is described in `photo-backup-Info.plist` (`NSPhotoLibraryUsageDescription`). The app reads the library for backup and duplicate detection; deleting duplicates uses `PHPhotoLibrary` change requests after you confirm.

## Contributing

Issues and pull requests are welcome. Keep changes focused; match existing Swift style and update tests when changing logic that is covered by `ArchiveAngelCoreTests`.

## Acknowledgements

- SwiftUI  
- Photos, AVFoundation, UIKit  

## Screenshots

![Screenshot 2024-07-12 at 2 02 53 PM](https://github.com/user-attachments/assets/9f26eeb4-23c9-4a0f-b9a8-c97b71109daa)
![Screenshot 2024-07-12 at 2 01 36 PM](https://github.com/user-attachments/assets/5f54796c-6c78-4280-af2c-00b31f282470)

![simulator_screenshot_C3CBD163-736D-49ED-8F9F-CA874D1FDBE6](https://github.com/user-attachments/assets/1ee8bb56-ed41-4c32-94d8-c764c75f86d2)
![simulator_screenshot_EC73F66F-529A-4CEB-90BA-FB79F527C938](https://github.com/user-attachments/assets/ffa47bb6-61ef-469e-8cba-6da257ca2833)
![simulator_screenshot_12FBBD51-1E9C-4EC8-92CD-B468A6973EA5](https://github.com/user-attachments/assets/09b19583-8294-4de1-aa17-93b84c146a66)
![simulator_screenshot_3FD44AC9-5C35-4687-AAEB-502517CA328B](https://github.com/user-attachments/assets/e9bc0e93-fba7-465c-a96d-a67bcb1a8ab9)
