import SwiftUI

// MARK: - Sidebar environment key

/// Set to `true` when a view is hosted inside the iPad sidebar's detail pane so it
/// can skip its own `NavigationView` wrapper (the sidebar already provides one).
struct InSidebarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inSidebar: Bool {
        get { self[InSidebarKey.self] }
        set { self[InSidebarKey.self] = newValue }
    }
}

// MARK: - Sidebar destination

private enum SidebarItem: String, Hashable, CaseIterable {
    case backup = "Backup"
    case history = "History"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .backup: return "externaldrive.fill.badge.icloud"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Root view

struct ArchiveAngelRootView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var sidebarSelection: SidebarItem? = .backup

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                sidebarBody
            } else {
                tabBody
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                viewModel.refreshMediaCounts()
                viewModel.refreshMissingCounts()
            }
        }
        .alert(item: alertItemBinding) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Backup folder", isPresented: bookmarkNoticePresented, actions: {
            Button("OK", role: .cancel) { viewModel.dismissBookmarkNotice() }
        }, message: {
            Text(viewModel.folderBookmarkStaleNotice ?? "")
        })
        .confirmationDialog(
            "Clear backup folder?",
            isPresented: clearFolderDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete all files inside folder", role: .destructive) {
                viewModel.performClearFolder()
            }
            Button("Cancel", role: .cancel) { viewModel.activeDialog = nil }
        } message: {
            Text("The folder stays selected; only its contents are removed.")
        }
        .confirmationDialog(
            "Delete duplicate photos?",
            isPresented: deleteDuplicatesDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete \(viewModel.scannedDuplicateLocalIds.count) photos", role: .destructive) {
                viewModel.confirmDeleteScannedDuplicates()
            }
            Button("Cancel", role: .cancel) { viewModel.cancelDuplicateDeletionDialog() }
        } message: {
            Text("One copy of each matching image is kept. Videos are not scanned. This cannot be undone.")
        }
        .confirmationDialog(
            "Low disk space",
            isPresented: lowDiskSpaceBackupDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Back up anyway") {
                viewModel.confirmBackupDespiteLowDiskSpace()
            }
            Button("Cancel", role: .cancel) {
                viewModel.activeDialog = nil
            }
        } message: {
            lowDiskSpaceBackupMessage
        }
    }

    private var alertItemBinding: Binding<ArchiveAngelAlert?> {
        Binding(
            get: { viewModel.alert },
            set: { viewModel.alert = $0 }
        )
    }

    private var bookmarkNoticePresented: Binding<Bool> {
        Binding(
            get: { viewModel.folderBookmarkStaleNotice != nil },
            set: { if !$0 { viewModel.dismissBookmarkNotice() } }
        )
    }

    private var clearFolderDialogPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeDialog == .clearFolder },
            set: { new in
                if !new { viewModel.activeDialog = nil }
            }
        )
    }

    private var deleteDuplicatesDialogPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeDialog == .deleteDuplicates },
            set: { new in
                if !new { viewModel.cancelDuplicateDeletionDialog() }
            }
        )
    }

    private var lowDiskSpaceBackupDialogPresented: Binding<Bool> {
        Binding(
            get: {
                if case .lowDiskSpaceBackup = viewModel.activeDialog { return true }
                return false
            },
            set: { new in
                if !new {
                    if case .lowDiskSpaceBackup = viewModel.activeDialog {
                        viewModel.activeDialog = nil
                    }
                }
            }
        )
    }

    // MARK: - Sidebar layout (iPad / regular horizontal size class)

    private var sidebarBody: some View {
        NavigationView {
            List {
                NavigationLink(tag: SidebarItem.backup, selection: $sidebarSelection) {
                    ContentView()
                } label: {
                    Label("Backup", systemImage: SidebarItem.backup.icon)
                }
                NavigationLink(tag: SidebarItem.history, selection: $sidebarSelection) {
                    HistoryView()
                        .environment(\.inSidebar, true)
                } label: {
                    Label("History", systemImage: SidebarItem.history.icon)
                }
                NavigationLink(tag: SidebarItem.settings, selection: $sidebarSelection) {
                    BackupSettingsView()
                        .environment(\.inSidebar, true)
                } label: {
                    Label("Settings", systemImage: SidebarItem.settings.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Archive Angel")

            // Default detail view shown before any sidebar selection
            ContentView()
        }
    }

    // MARK: - Tab layout (iPhone / compact horizontal size class)

    private var tabBody: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Backup", systemImage: SidebarItem.backup.icon)
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: SidebarItem.history.icon)
                }
            BackupSettingsView()
                .tabItem {
                    Label("Settings", systemImage: SidebarItem.settings.icon)
                }
        }
    }

    // MARK: - Low disk space message

    @ViewBuilder
    private var lowDiskSpaceBackupMessage: some View {
        switch viewModel.activeDialog {
        case let .lowDiskSpaceBackup(freeBytes, neededBytes):
            let freeFormatted = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
            let neededFormatted = ByteCountFormatter.string(fromByteCount: neededBytes, countStyle: .file)
            Text(
                "About \(freeFormatted) free; new items are estimated around \(neededFormatted). The export may stop if the disk fills. Continue?"
            )
        default:
            Text("")
        }
    }
}

struct ArchiveAngelRootView_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveAngelRootView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
