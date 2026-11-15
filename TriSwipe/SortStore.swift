import Foundation
import Photos
import Observation
import UIKit

/// Le « cerveau » de l'appli : index des photos, session de tri, corbeille, stats.
@MainActor
@Observable
final class SortStore {

    // MARK: État affiché

    var authorization: PHAuthorizationStatus = PhotoService.currentStatus()
    var isLoading = false
    var errorMessage: String?

    var albums: [AlbumInfo] = []
    var months: [MonthGroup] = []
    var quickCounts: [SortSource: Int] = [:]

    var mediaFilter: MediaFilter = .all { didSet { refreshSummaries() } }
    var order: SortOrder = .newest

    var session: SortSession?
    private(set) var history: [UndoAction] = []

    // MARK: Données sauvegardées

    private(set) var reviewed: Set<String> = []
    private(set) var trash: [String: Int64] = [:]
    private(set) var recentAlbumIDs: [String] = []
    private(set) var stats = Stats()
    private(set) var pinnedAlbumIDs: [String] = []
    private var pinsInitialized = false
    private(set) var cleanups: [CleanupRecord] = []
    private(set) var deletedByMonth: [String: Int] = [:]
    private(set) var bytesByMonth: [String: Int64] = [:]
    private(set) var lastMonth: String?

    // MARK: Index interne

    private var index: [AssetInfo] = []
    private var positionByID: [String: Int] = [:]
    private var saveTask: Task<Void, Never>?

    var isAuthorized: Bool { authorization == .authorized || authorization == .limited }
    var trashCount: Int { trash.count }
    var trashBytes: Int64 { trash.values.reduce(0, +) }
    var trashIDs: [String] {
        trash.keys.sorted { (info(for: $0)?.date ?? .distantPast) > (info(for: $1)?.date ?? .distantPast) }
    }
    var recentAlbums: [AlbumInfo] {
        recentAlbumIDs.compactMap { id in albums.first { $0.id == id } }
    }
    var pinnedAlbums: [AlbumInfo] {
        pinnedAlbumIDs.compactMap { id in albums.first { $0.id == id } }
    }
    /// Raccourcis affichés sous la photo : albums épinglés puis derniers utilisés.
    var shortcutAlbums: [AlbumInfo] {
        let pinned = pinnedAlbums
        let others = recentAlbums.filter { a in !pinned.contains { $0.id == a.id } }
        return Array((pinned + others).prefix(10))
    }
    func isPinned(_ id: String) -> Bool { pinnedAlbumIDs.contains(id) }
    func togglePin(_ id: String) {
        if let i = pinnedAlbumIDs.firstIndex(of: id) { pinnedAlbumIDs.remove(at: i) } else { pinnedAlbumIDs.append(id) }
        scheduleSave()
    }

    /// Le dernier mois commencé et pas encore terminé.
    var resumeMonth: MonthGroup? {
        guard let key = lastMonth else { return nil }
        return months.first { String(format: "%04d-%02d", $0.year, $0.month) == key && $0.remaining > 0 }
    }
    func deleted(in m: MonthGroup) -> Int { deletedByMonth[String(format: "%04d-%02d", m.year, m.month)] ?? 0 }
    func bytesFreed(in m: MonthGroup) -> Int64 { bytesByMonth[String(format: "%04d-%02d", m.year, m.month)] ?? 0 }

    init() {
        loadPersisted()
    }

    // MARK: Chargement

    func requestAccess() async {
        authorization = await PhotoService.requestAuthorization()
        await load()
    }

    func load() async {
        guard isAuthorized else { return }
        isLoading = true
        let list = await Task.detached { PhotoService.loadIndex() }.value
        let albumList = await Task.detached { PhotoService.userAlbums() }.value
        setIndex(list)
        albums = albumList
        // On oublie ce qui a été supprimé depuis l'app Photos.
        trash = trash.filter { positionByID[$0.key] != nil }
        recentAlbumIDs = recentAlbumIDs.filter { id in albumList.contains { $0.id == id } }
        if !pinsInitialized {
            // Raccourcis proposés par défaut, d'après la structure de la photothèque.
            let wanted = ["1- DRAG", "WIG /HAIR", "4- MOODBOARD", "Mêmes", "Papiers & documents"]
            pinnedAlbumIDs = wanted.compactMap { name in
                albumList.first { $0.title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }?.id
            }
            pinsInitialized = true
            scheduleSave()
        }
        refreshSummaries()
        isLoading = false
    }

    func reloadAlbums() async {
        albums = await Task.detached { PhotoService.userAlbums() }.value
    }

    private func setIndex(_ list: [AssetInfo]) {
        index = list
        var map: [String: Int] = [:]
        map.reserveCapacity(list.count)
        for (i, a) in list.enumerated() { map[a.id] = i }
        positionByID = map
    }

    func info(for id: String) -> AssetInfo? {
        guard let i = positionByID[id], i < index.count else { return nil }
        return index[i]
    }

    func isDone(_ id: String) -> Bool {
        reviewed.contains(id) || trash[id] != nil
    }

    // MARK: Résumés pour l'écran d'accueil

    func refreshSummaries() {
        let calendar = Calendar.current
        var counts: [Int: (total: Int, remaining: Int)] = [:]
        for a in index where mediaFilter.matches(a) {
            let c = calendar.dateComponents([.year, .month], from: a.date)
            let key = (c.year ?? 0) * 100 + (c.month ?? 0)
            var entry = counts[key] ?? (0, 0)
            entry.total += 1
            if !isDone(a.id) { entry.remaining += 1 }
            counts[key] = entry
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL yyyy"

        months = counts.keys.sorted(by: >).compactMap { key in
            guard let entry = counts[key] else { return nil }
            let year = key / 100, month = key % 100
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
            return MonthGroup(
                year: year, month: month,
                title: formatter.string(from: date).capitalized,
                total: entry.total, remaining: entry.remaining
            )
        }

        var quick: [SortSource: Int] = [:]
        for source in [SortSource.all, .onThisDay, .screenshots, .longVideos] {
            quick[source] = items(for: source).count
        }
        quickCounts = quick
    }

    private func items(for source: SortSource) -> [AssetInfo] {
        let calendar = Calendar.current
        let pending = index.filter { !isDone($0.id) }

        switch source {
        case .all:
            return pending.filter { mediaFilter.matches($0) }

        case .onThisDay:
            let today = calendar.dateComponents([.year, .month, .day], from: Date())
            return pending.filter { a in
                guard mediaFilter.matches(a) else { return false }
                let c = calendar.dateComponents([.year, .month, .day], from: a.date)
                return c.month == today.month && c.day == today.day && (c.year ?? 0) < (today.year ?? 0)
            }

        case .screenshots:
            return pending.filter { $0.isScreenshot }

        case .longVideos:
            return pending.filter { $0.isVideo }.sorted { $0.duration > $1.duration }

        case let .month(year, month):
            return pending.filter { a in
                guard mediaFilter.matches(a) else { return false }
                let c = calendar.dateComponents([.year, .month], from: a.date)
                return c.year == year && c.month == month
            }

        case let .album(albumID):
            return PhotoService.assetIDs(inAlbum: albumID).compactMap { id in
                guard !isDone(id), let a = info(for: id) else { return nil }
                return a
            }
        }
    }

    // MARK: Session de tri

    func start(_ source: SortSource, title: String) {
        var list = items(for: source)
        if source != .longVideos {
            switch order {
            case .newest: break
            case .oldest: list.reverse()
            case .random: list.shuffle()
            }
        }
        history.removeAll()
        var newSession = SortSession(title: title, queue: list.map(\.id))
        switch source {
        case let .album(albumID): newSession.sourceAlbumID = albumID
        case let .month(year, month):
            lastMonth = String(format: "%04d-%02d", year, month)
            scheduleSave()
        default: break
        }
        session = newSession
    }

    func endSession() {
        session = nil
        history.removeAll()
        refreshSummaries()
        saveNow()
    }

    var currentID: String? { id(at: 0) }
    var nextID: String? { id(at: 1) }

    private func id(at offset: Int) -> String? {
        guard let s = session else { return nil }
        let i = s.position + offset
        return i < s.queue.count ? s.queue[i] : nil
    }

    var progressText: String {
        guard let s = session else { return "" }
        return "\(min(s.position + 1, s.queue.count)) / \(s.queue.count)"
    }

    var remainingInSession: Int {
        guard let s = session else { return 0 }
        return max(s.queue.count - s.position, 0)
    }

    private func advance() {
        session?.position += 1
        scheduleSave()
    }

    // MARK: Les 4 gestes

    func keep() {
        guard let id = currentID else { return }
        reviewed.insert(id)
        stats.kept += 1
        history.append(UndoAction(id: id, decision: .keep, albumID: nil))
        advance()
        // En tri d'album (ex. « À vérifier avant suppression »), garder = sortir de l'album.
        if let source = session?.sourceAlbumID {
            Task { try? await PhotoService.remove([id], fromAlbum: source) }
        }
    }

    func delete() {
        guard let id = currentID else { return }
        trash[id] = PhotoService.fileSize(for: id)
        history.append(UndoAction(id: id, decision: .delete, albumID: nil))
        advance()
    }

    func skip() {
        guard let id = currentID else { return }
        history.append(UndoAction(id: id, decision: .skip, albumID: nil))
        advance()
    }

    func addToAlbum(_ albumID: String) {
        guard let id = currentID else { return }
        reviewed.insert(id)
        stats.albumed += 1
        recentAlbumIDs.removeAll { $0 == albumID }
        recentAlbumIDs.insert(albumID, at: 0)
        if recentAlbumIDs.count > 8 { recentAlbumIDs.removeLast() }
        history.append(UndoAction(id: id, decision: .album, albumID: albumID))
        let source = session?.sourceAlbumID
        advance()
        Task {
            do {
                try await PhotoService.add([id], toAlbum: albumID)
                if let source, source != albumID { try await PhotoService.remove([id], fromAlbum: source) }
            } catch { errorMessage = "Impossible d'ajouter à l'album : \(error.localizedDescription)" }
        }
    }

    var canUndo: Bool { !history.isEmpty }

    func undo() {
        guard let last = history.popLast(), var s = session, s.position > 0 else { return }
        switch last.decision {
        case .keep:
            reviewed.remove(last.id)
            stats.kept = max(stats.kept - 1, 0)
            if let source = s.sourceAlbumID {
                Task { try? await PhotoService.add([last.id], toAlbum: source) }
            }
        case .delete:
            trash[last.id] = nil
        case .album:
            reviewed.remove(last.id)
            stats.albumed = max(stats.albumed - 1, 0)
            if let albumID = last.albumID {
                let source = s.sourceAlbumID
                Task {
                    try? await PhotoService.remove([last.id], fromAlbum: albumID)
                    if let source, source != albumID { try? await PhotoService.add([last.id], toAlbum: source) }
                }
            }
        case .skip:
            break
        }
        s.position -= 1
        session = s
        scheduleSave()
    }

    func toggleFavorite(_ id: String) {
        guard let i = positionByID[id] else { return }
        let newValue = !index[i].isFavorite
        index[i].isFavorite = newValue
        Task {
            do { try await PhotoService.setFavorite(id, newValue) }
            catch {
                if let j = positionByID[id] { index[j].isFavorite = !newValue }
                errorMessage = "Impossible de modifier le favori."
            }
        }
    }

    // MARK: Albums

    func createAlbum(named name: String) async -> String? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        do {
            let id = try await PhotoService.createAlbum(named: title)
            await reloadAlbums()
            return id
        } catch {
            errorMessage = "Impossible de créer l'album : \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Corbeille

    func restore(_ id: String) {
        trash[id] = nil
        history.removeAll { $0.id == id && $0.decision == .delete }
        refreshSummaries()
        scheduleSave()
    }

    func restoreAll() {
        trash.removeAll()
        history.removeAll { $0.decision == .delete }
        refreshSummaries()
        scheduleSave()
    }

    /// Supprime pour de vrai et renvoie le récap (nil si annulé).
    @discardableResult
    func emptyTrash() async -> CleanupRecord? {
        let ids = Array(trash.keys)
        guard !ids.isEmpty else { return nil }
        do {
            try await PhotoService.delete(ids)
        } catch {
            // 3072 = l'utilisateur a appuyé sur « Ne pas autoriser » dans la confirmation iOS.
            if (error as NSError).code != 3072 {
                errorMessage = "La suppression a échoué : \(error.localizedDescription)"
            }
            return nil
        }

        let bytes = ids.reduce(Int64(0)) { $0 + (trash[$1] ?? 0) }
        var videos = 0
        for id in ids {
            guard let a = info(for: id) else { continue }
            if a.isVideo { videos += 1 }
            let key = monthKey(a.date)
            deletedByMonth[key, default: 0] += 1
            bytesByMonth[key, default: 0] += trash[id] ?? 0
        }
        let record = CleanupRecord(date: Date(), count: ids.count, videos: videos, bytes: bytes)
        cleanups.insert(record, at: 0)
        stats.deleted += ids.count
        stats.bytesFreed += bytes
        trash.removeAll()
        history.removeAll()

        let removed = Set(ids)
        setIndex(index.filter { !removed.contains($0.id) })
        if var s = session {
            let before = s.queue.prefix(s.position).filter { removed.contains($0) }.count
            s.queue.removeAll { removed.contains($0) }
            s.position = max(s.position - before, 0)
            session = s
        }
        refreshSummaries()
        saveNow()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return record
    }

    func resetProgress() {
        reviewed.removeAll()
        stats = Stats()
        refreshSummaries()
        saveNow()
    }

    // MARK: Sauvegarde

    private var stateURL: URL {
        URL.documentsDirectory.appending(path: "triswipe-state.json")
    }

    private func loadPersisted() {
        guard
            let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }
        reviewed = Set(state.reviewed)
        trash = state.trash
        recentAlbumIDs = state.recentAlbums
        stats = state.stats
        pinnedAlbumIDs = state.pinnedAlbums
        pinsInitialized = state.pinsInitialized
        cleanups = state.cleanups
        deletedByMonth = state.deletedByMonth
        bytesByMonth = state.bytesByMonth
        lastMonth = state.lastMonth
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            saveNow()
        }
    }

    func saveNow() {
        let state = PersistedState(
            reviewed: Array(reviewed),
            trash: trash,
            recentAlbums: recentAlbumIDs,
            stats: stats,
            pinnedAlbums: pinnedAlbumIDs,
            pinsInitialized: pinsInitialized,
            cleanups: cleanups,
            deletedByMonth: deletedByMonth,
            bytesByMonth: bytesByMonth,
            lastMonth: lastMonth
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
