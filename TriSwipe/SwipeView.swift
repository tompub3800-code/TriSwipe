import SwiftUI

/// L'écran de tri : une carte, quatre directions.
/// → droite : garder · ← gauche : corbeille · ↑ haut : album · ↓ bas : plus tard
@MainActor
struct SwipeView: View {
    @Environment(SortStore.self) private var store
    @State private var offset: CGSize = .zero
    @State private var showAlbumPicker = false
    @State private var showTrash = false
    @State private var isAnimating = false

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 14) {
            topBar

            ZStack {
                if let next = store.nextID {
                    MediaCard(id: next, isActive: false)
                        .id("next-\(next)")
                        .scaleEffect(0.94)
                        .opacity(0.5)
                }

                if let id = store.currentID {
                    MediaCard(id: id, isActive: true)
                        .id("current-\(id)")
                        .overlay { swipeLabel }
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .highPriorityGesture(dragGesture)
                        .onTapGesture(count: 2) {
                            store.toggleFavorite(id)
                            haptic(.light)
                        }
                } else {
                    finishedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)

            if store.currentID != nil {
                albumChips
                actionButtons
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerView { albumID in
                showAlbumPicker = false
                fly(.album, albumID: albumID)
            }
        }
        .sheet(isPresented: $showTrash) {
            TrashView()
        }
        .alert("Oups", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: Barre du haut

    private var topBar: some View {
        HStack {
            Button {
                store.endSession()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(store.session?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(store.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    store.undo()
                    haptic(.light)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .disabled(!store.canUndo)

                Button {
                    showTrash = true
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if store.trashCount > 0 {
                                Text("\(store.trashCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.red, in: Capsule())
                                    .offset(x: 6, y: -4)
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Étiquette pendant le glissement

    private var swipeLabel: some View {
        let (text, color, icon) = labelInfo
        let strength = min(max(abs(offset.width), abs(offset.height)) / threshold, 1)
        return VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 44, weight: .bold))
            Text(text).font(.title2.weight(.heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(text.isEmpty ? 0 : strength)
        .allowsHitTesting(false)
    }

    private var labelInfo: (String, Color, String) {
        let w = offset.width, h = offset.height
        if abs(w) < 20 && abs(h) < 20 { return ("", .clear, "circle") }
        if abs(w) >= abs(h) {
            return w > 0 ? ("GARDER", .green, "checkmark") : ("SUPPRIMER", .red, "trash")
        } else {
            return h < 0 ? ("ALBUM", .blue, "folder.badge.plus") : ("PLUS TARD", .gray, "clock")
        }
    }

    // MARK: Geste

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimating else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimating else { return }
                let w = value.translation.width, h = value.translation.height
                let pw = value.predictedEndTranslation.width, ph = value.predictedEndTranslation.height
                if abs(w) >= abs(h) {
                    if w > threshold || pw > threshold * 2.5 { fly(.keep); return }
                    if w < -threshold || pw < -threshold * 2.5 { fly(.delete); return }
                } else {
                    if h < -threshold || ph < -threshold * 2.5 {
                        withAnimation(.spring(duration: 0.3)) { offset = .zero }
                        showAlbumPicker = true
                        return
                    }
                    if h > threshold || ph > threshold * 2.5 { fly(.skip); return }
                }
                withAnimation(.spring(duration: 0.3)) { offset = .zero }
            }
    }

    /// Fait partir la carte dans la bonne direction, puis applique la décision.
    private func fly(_ decision: Decision, albumID: String? = nil) {
        guard store.currentID != nil, !isAnimating else { return }
        isAnimating = true

        let target: CGSize
        switch decision {
        case .keep: target = CGSize(width: 600, height: offset.height)
        case .delete: target = CGSize(width: -600, height: offset.height)
        case .album: target = CGSize(width: 0, height: -900)
        case .skip: target = CGSize(width: 0, height: 900)
        }

        haptic(decision == .delete ? .rigid : .medium)
        withAnimation(.easeIn(duration: 0.18)) { offset = target }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch decision {
                case .keep: store.keep()
                case .delete: store.delete()
                case .skip: store.skip()
                case .album:
                    if let albumID { store.addToAlbum(albumID) }
                }
                offset = .zero
            }
            isAnimating = false
        }
    }

    // MARK: Albums rapides

    private var albumChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showAlbumPicker = true
                } label: {
                    Label("Album", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }

                ForEach(store.shortcutAlbums) { album in
                    Button {
                        fly(.album, albumID: album.id)
                    } label: {
                        Text(album.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Boutons

    private var actionButtons: some View {
        HStack(spacing: 18) {
            roundButton("trash.fill", color: .red, size: 64) { fly(.delete) }
            roundButton("clock.fill", color: .gray, size: 50) { fly(.skip) }
            roundButton("folder.fill.badge.plus", color: .blue, size: 50) { showAlbumPicker = true }
            roundButton("checkmark", color: .green, size: 64) { fly(.keep) }
        }
        .padding(.top, 2)
    }

    private func roundButton(_ icon: String, color: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
        .disabled(isAnimating)
    }

    // MARK: Fin de session

    private var finishedView: some View {
        VStack(spacing: 18) {
            Text("🎉").font(.system(size: 64))
            Text("Tout est trié !")
                .font(.title.bold())
            if store.trashCount > 0 {
                Text("\(store.trashCount) élément(s) dans la corbeille · \(formatBytes(store.trashBytes)) à libérer")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    showTrash = true
                } label: {
                    Label("Vérifier et vider la corbeille", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            Button("Retour à l'accueil") { store.endSession() }
                .buttonStyle(.bordered)
                .controlSize(.large)
            if store.canUndo {
                Button("Annuler le dernier geste") { store.undo() }
                    .font(.footnote)
            }
        }
        .padding(32)
    }

    // MARK: Outils

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
