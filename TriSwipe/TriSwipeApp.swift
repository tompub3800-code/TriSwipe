import SwiftUI
import Photos

@main
struct TriSwipeApp: App {
    @State private var store = SortStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.pink)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
        }
    }
}

@MainActor
struct RootView: View {
    @Environment(SortStore.self) private var store

    var body: some View {
        Group {
            switch store.authorization {
            case .authorized, .limited:
                HomeView()
            case .notDetermined:
                welcome
            default:
                denied
            }
        }
        .task { await store.load() }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 72))
                .foregroundStyle(.pink)
            Text("TriSwipe")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 12) {
                tip("arrow.right", .green, "Glisse à droite pour garder")
                tip("arrow.left", .red, "Glisse à gauche pour jeter")
                tip("arrow.up", .blue, "Glisse vers le haut pour ranger dans un album")
                tip("arrow.down", .gray, "Glisse vers le bas pour décider plus tard")
                tip("hand.tap", .pink, "Touche deux fois pour mettre en favori")
            }
            .padding(.horizontal, 32)
            Spacer()
            Button {
                Task { await store.requestAccess() }
            } label: {
                Text("Autoriser l'accès aux photos")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            Text("Tout reste sur ton téléphone. Rien n'est envoyé nulle part.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
    }

    private func tip(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: Circle())
            Text(text)
        }
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("Accès aux photos refusé", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Pour trier tes photos, autorise l'accès complet dans Réglages > TriSwipe > Photos.")
        } actions: {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
