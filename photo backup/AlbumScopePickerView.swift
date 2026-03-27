import SwiftUI

/// Full-screen style picker for choosing many albums without cramming Settings.
struct AlbumScopePickerView: View {
    @Binding var selectedIds: Set<String>
    let albums: [PickableAlbum]
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var draftSelected = Set<String>()

    var body: some View {
        NavigationView {
            Group {
                if albums.isEmpty {
                    ContentUnavailablePlaceholder(
                        title: "No albums",
                        message: "Allow photo access and tap Refresh on the previous screen, then try again."
                    )
                } else {
                    albumList
                }
            }
            .navigationTitle("Choose albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Search albums"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Select all matching search") {
                            for album in filteredAlbums {
                                draftSelected.insert(album.id)
                            }
                        }
                        .disabled(filteredAlbums.isEmpty)
                        Button("Deselect all matching search") {
                            for album in filteredAlbums {
                                draftSelected.remove(album.id)
                            }
                        }
                        .disabled(filteredAlbums.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Bulk actions for visible albums")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedIds = draftSelected
                        onApply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftSelected = selectedIds
            }
        }
        .navigationViewStyle(.stack)
    }

    private var filteredAlbums: [PickableAlbum] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var userAlbumsFiltered: [PickableAlbum] {
        filteredAlbums.filter { $0.kindLabel == "Album" }
    }

    private var smartAlbumsFiltered: [PickableAlbum] {
        filteredAlbums.filter { $0.kindLabel == "Smart album" }
    }

    private var albumList: some View {
        List {
            if filteredAlbums.isEmpty {
                Section {
                    Text(emptyFilterMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                if !userAlbumsFiltered.isEmpty {
                    Section {
                        ForEach(userAlbumsFiltered) { album in
                            albumRow(album)
                        }
                    } header: {
                        Text("Albums (\(userAlbumsFiltered.count))")
                    }
                }
                if !smartAlbumsFiltered.isEmpty {
                    Section {
                        ForEach(smartAlbumsFiltered) { album in
                            albumRow(album)
                        }
                    } header: {
                        Text("Smart albums (\(smartAlbumsFiltered.count))")
                    }
                }
            }

            Section {
                Text(
                    selectedSummary
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyFilterMessage: String {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return "No albums to show."
        }
        return "No albums match “\(q)”."
    }

    private var selectedSummary: String {
        let n = draftSelected.count
        if n == 0 {
            return "None selected — backup uses your entire library."
        }
        return "\(n) album\(n == 1 ? "" : "s") selected for backup scope."
    }

    private func albumRow(_ album: PickableAlbum) -> some View {
        Button {
            if draftSelected.contains(album.id) {
                draftSelected.remove(album.id)
            } else {
                draftSelected.insert(album.id)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Text(album.kindLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: draftSelected.contains(album.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(draftSelected.contains(album.id) ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(album.title)
        .accessibilityValue(draftSelected.contains(album.id) ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to toggle selection.")
    }
}

/// Simple placeholder when `ContentUnavailableView` is not available (keeps iOS 15 support).
private struct ContentUnavailablePlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
