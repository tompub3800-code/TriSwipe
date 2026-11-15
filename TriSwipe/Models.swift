import Foundation

/// Infos légères sur une photo/vidéo (lues une seule fois au chargement).
struct AssetInfo: Hashable, Sendable {
    let id: String
    let date: Date
    let isVideo: Bool
    let isScreenshot: Bool
    let duration: Double
    var isFavorite: Bool
}

struct AlbumInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
    /// Dossier(s) qui contiennent l'album, ex. « 3- SOCIALS » (vide si à la racine).
    let path: String
}

/// Un passage de corbeille validé.
struct CleanupRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let count: Int
    let videos: Int
    let bytes: Int64
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "Tout"
    case photos = "Photos"
    case videos = "Vidéos"

    var id: String { rawValue }

    func matches(_ a: AssetInfo) -> Bool {
        switch self {
        case .all: return true
        case .photos: return !a.isVideo
        case .videos: return a.isVideo
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case newest = "Récentes"
    case oldest = "Anciennes"
    case random = "Au hasard"

    var id: String { rawValue }
}

/// Ce qu'on trie dans une session.
enum SortSource: Hashable {
    case all
    case onThisDay
    case screenshots
    case longVideos
    case month(year: Int, month: Int)
    case album(String)
}

enum Decision: String, Codable {
    case keep, delete, album, skip
}

struct UndoAction {
    let id: String
    let decision: Decision
    let albumID: String?
}

struct MonthGroup: Identifiable, Hashable {
    let year: Int
    let month: Int
    let title: String
    let total: Int
    let remaining: Int

    var id: Int { year * 100 + month }
    var progress: Double { total == 0 ? 1 : Double(total - remaining) / Double(total) }
}

struct Stats: Codable {
    var kept = 0
    var deleted = 0
    var albumed = 0
    var bytesFreed: Int64 = 0

    var sorted: Int { kept + deleted + albumed }
}

/// Ce qui est sauvegardé entre deux lancements de l'appli.
struct PersistedState: Codable {
    var reviewed: [String] = []
    var trash: [String: Int64] = [:]
    var recentAlbums: [String] = []
    var stats = Stats()
    var pinnedAlbums: [String] = []
    var pinsInitialized = false
    var cleanups: [CleanupRecord] = []
    var deletedByMonth: [String: Int] = [:]
    var bytesByMonth: [String: Int64] = [:]
    var lastMonth: String? = nil
}

struct SortSession {
    let title: String
    var queue: [String]
    var position = 0
    /// Rempli quand on trie un album : « garder » retire alors la photo de cet album.
    var sourceAlbumID: String? = nil
}

func monthKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}
