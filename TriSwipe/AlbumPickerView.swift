import SwiftUI

/// Choisir un album, présenté selon ta structure de dossiers (1- DRAG, 3- SOCIALS…).
/// Sert à ranger la photo en cours, ou à choisir un album à trier.
@MainActor
struct AlbumPickerView: View {
    var title = "Ranger dans…"
    var allowCreate = true
    let onPick: (String) -> Void

    @Environment(SortStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var newName = ""
    @State private var isCreating = false

    private var filtered: [AlbumInfo] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.albums }
        return store.albums.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    /// Albums regroupés par dossier, dans l'ordre 1-, 2-, 3-…
    private var groups: [(path: String, albums: [AlbumInfo])] {
        let byPath = Dictionary(grouping: filtered, by: \.path)
        return byPath.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return a.isEmpty }
            return a.localizedStandardCompare(b) == .orderedAscending
        }.map { key in
            (key, (byPath[key] ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if allowCreate {
                    Section {
                        HStack {
                            TextField("Nouvel album…", text: $newName)
                                .submitLabel(.done)
                                .onSubmit { create() }
                            if isCreating {
                                ProgressView()
                            } else {
                                Button("Créer", action: create)
                                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    } header: {
                        Text("Créer et ranger dedans")
                    }
                }

                if search.isEmpty && !store.pinnedAlbums.isEmpty {
                    Section("Épinglés") {
                        ForEach(store.pinnedAlbums) { album in row(album, showPath: true) }
                    }
                }

                if filtered.isEmpty {
                    Text("Aucun album").foregroundStyle(.secondary)
                }

                ForEach(groups, id: \.path) { group in
                    Section {
                        ForEach(group.albums) { album in row(album, showPath: false) }
                    } header: {
                        Label(group.path.isEmpty ? "Albums" : group.path,
                              systemImage: group.path.isEmpty ? "rectangle.stack" : "folder")
                    }
                }
            }
            .searchable(text: $search, prompt: "Rechercher un album")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ album: AlbumInfo, showPath: Bool) -> some View {
        HStack {
            Button {
                onPick(album.id)
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(album.title).foregroundStyle(.primary)
                        if showPath && !album.path.isEmpty {
                            Text(album.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(album.count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .buttonStyle(.borderless)

            Button {
                store.togglePin(album.id)
            } label: {
                Image(systemName: store.isPinned(album.id) ? "pin.fill" : "pin")
                    .foregroundStyle(store.isPinned(album.id) ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func create() {
        let name = newName
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !isCreating else { return }
        isCreating = true
        Task {
            let id = await store.createAlbum(named: name)
            isCreating = false
            if let id {
                newName = ""
                onPick(id)
            }
        }
    }
}
