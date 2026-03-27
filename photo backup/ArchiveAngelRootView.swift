import SwiftUI

struct ArchiveAngelRootView: View {
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
        }
    }
}

struct ArchiveAngelRootView_Previews: PreviewProvider {
    static var previews: some View {
        ArchiveAngelRootView()
            .environmentObject(ArchiveAngelViewModel())
    }
}
