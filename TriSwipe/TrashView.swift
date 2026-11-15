import SwiftUI

/// Dernière vérification avant de supprimer pour de vrai.
@MainActor
struct TrashView: View {
    @Environment(SortStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false
    @State private var recap: CleanupRecord?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if let recap {
                    RecapView(record: recap) { dismiss() }
                } else if store.trashCount == 0 {
                    ContentUnavailableView(
                        "Corbeille vide",
                        systemImage: "trash",
                        description: Text("Les photos glissées vers la gauche arrivent ici. Rien n'est supprimé tant que tu n'as pas validé.")
                    )
                } else {
                    ScrollView {
                        Text("Touche une photo pour la récupérer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(store.trashIDs, id: \.self) { id in
                                Button {
                                    withAnimation { store.restore(id) }
                                } label: {
                                    Thumbnail(id: id)
                                        .overlay(alignment: .bottomTrailing) {
                                            if store.info(for: id)?.isVideo == true {
                                                Image(systemName: "video.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                                    .shadow(radius: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 120)
                    }
                    .safeAreaInset(edge: .bottom) { deleteBar }
                }
            }
            .navigationTitle("Corbeille")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if store.trashCount > 0 && recap == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Tout récupérer") { withAnimation { store.restoreAll() } }
                    }
                }
            }
        }
    }

    private var deleteBar: some View {
        VStack(spacing: 6) {
            Button {
                isDeleting = true
                Task {
                    let result = await store.emptyTrash()
                    isDeleting = false
                    if let result { withAnimation { recap = result } }
                }
            } label: {
                HStack {
                    if isDeleting { ProgressView().tint(.white) }
                    Text("Supprimer \(store.trashCount) élément(s) · \(formatBytes(store.trashBytes))")
                        .bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(isDeleting)

            Text("Ils iront dans « Supprimés récemment » de l'app Photos pendant 30 jours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.bar)
    }
}
