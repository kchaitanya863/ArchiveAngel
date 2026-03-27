import SwiftUI

struct ArchiveAngelRootView: View {
    @EnvironmentObject private var viewModel: ArchiveAngelViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Backup", systemImage: "externaldrive.fill.badge.icloud")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            BackupSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
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
}

struct ArchiveAngelRootView_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveAngelRootView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
