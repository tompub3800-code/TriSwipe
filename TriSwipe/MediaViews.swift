import SwiftUI
import AVKit

/// Garde en mémoire les dernières grandes images pour que le passage d'une carte à l'autre soit instantané.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var images: [String: UIImage] = [:]
    private var order: [String] = []

    func get(_ id: String) -> UIImage? { images[id] }

    func set(_ image: UIImage, for id: String) {
        if images[id] == nil { order.append(id) }
        images[id] = image
        if order.count > 20 {
            let old = order.removeFirst()
            images[old] = nil
        }
    }
}

/// La grande carte affichée pendant le tri.
@MainActor
struct MediaCard: View {
    let id: String
    let isActive: Bool

    @Environment(SortStore.self) private var store
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var sizeText = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        let info = store.info(for: id)

        ZStack(alignment: .bottom) {
            Color.black

            if let player, isActive {
                VideoPlayer(player: player)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }

            if isActive, let info {
                HStack(spacing: 8) {
                    if info.isVideo {
                        Label(formatDuration(info.duration), systemImage: "video.fill")
                    }
                    Text(Self.dateFormatter.string(from: info.date))
                    if !sizeText.isEmpty {
                        Text("· \(sizeText)")
                    }
                    Spacer()
                    if info.isFavorite {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .padding(12)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .task(id: id) { await load(isVideo: info?.isVideo == true) }
        .onDisappear { player?.pause() }
    }

    private func load(isVideo: Bool) async {
        if let cached = ImageCache.shared.get(id) {
            image = cached
        } else {
            let loaded = await PhotoService.image(for: id, size: CGSize(width: 1400, height: 1400))
            if let loaded {
                ImageCache.shared.set(loaded, for: id)
            }
            image = loaded
        }

        guard isActive else { return }

        let assetID = id
        let bytes = await Task.detached { PhotoService.fileSize(for: assetID) }.value
        sizeText = formatBytes(bytes)

        if isVideo, let item = await PhotoService.playerItem(for: assetID) {
            let p = AVPlayer(playerItem: item)
            p.isMuted = true
            p.play()
            player = p
        }
    }
}

/// Petite vignette carrée (corbeille).
@MainActor
struct Thumbnail: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: id) {
                image = await PhotoService.image(for: id, size: CGSize(width: 300, height: 300))
            }
    }
}
