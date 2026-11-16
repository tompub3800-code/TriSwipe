import Photos
import UIKit
import AVFoundation

/// Petite boîte pour récupérer une valeur depuis un bloc de modification Photos.
final class ValueBox: @unchecked Sendable {
    var value: String?
}

/// Tout ce qui parle à la photothèque de l'iPhone.
/// On passe toujours par les identifiants (String) pour rester simple et sûr.
enum PhotoService {

    // MARK: Autorisation

    nonisolated static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    nonisolated static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Lecture

    nonisolated static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Charge l'index de toute la photothèque (photos + vidéos), du plus récent au plus ancien.
    nonisolated static func loadIndex() -> [AssetInfo] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %@ OR mediaType == %@",
            NSNumber(value: PHAssetMediaType.image.rawValue),
            NSNumber(value: PHAssetMediaType.video.rawValue)
        )
        let result = PHAsset.fetchAssets(with: options)
        var list: [AssetInfo] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { a, _, _ in
            list.append(AssetInfo(
                id: a.localIdentifier,
                date: a.creationDate ?? .distantPast,
                isVideo: a.mediaType == .video,
                isScreenshot: a.mediaSubtypes.contains(.photoScreenshot),
                duration: a.duration,
                isFavorite: a.isFavorite
            ))
        }
        return list
    }

    /// Tous les albums créés par l'utilisateur, y compris ceux rangés dans des dossiers.
    nonisolated static func userAlbums() -> [AlbumInfo] {
        var out: [AlbumInfo] = []
        func walk(_ list: PHFetchResult<PHCollection>, path: String) {
            list.enumerateObjects { c, _, _ in
                if let album = c as? PHAssetCollection {
                    guard album.assetCollectionSubtype == .albumRegular else { return }
                    let count = album.estimatedAssetCount == NSNotFound ? 0 : album.estimatedAssetCount
                    out.append(AlbumInfo(id: album.localIdentifier,
                                         title: album.localizedTitle ?? "Sans titre",
                                         count: count, path: path))
                } else if let folder = c as? PHCollectionList {
                    let name = folder.localizedTitle ?? "Dossier"
                    walk(PHCollection.fetchCollections(in: folder, options: nil),
                         path: path.isEmpty ? name : path + " › " + name)
                }
            }
        }
        walk(PHCollection.fetchTopLevelUserCollections(with: nil), path: "")
        return out
    }

    /// Identifiants des photos/vidéos d'un album, des plus récentes aux plus anciennes.
    nonisolated static func assetIDs(inAlbum albumID: String) -> [String] {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { a, _, _ in
            ids.append(a.localIdentifier)
        }
        return ids
    }

    /// Toutes les photos déjà rangées dans au moins un album perso,
    /// sauf les albums dont l'id est dans `excluding` (ex. albums de pré-tri).
    nonisolated static func filedAssetIDs(excluding: Set<String>) -> Set<String> {
        var ids = Set<String>()
        for album in userAlbums() where !excluding.contains(album.id) {
            ids.formUnion(assetIDs(inAlbum: album.id))
        }
        return ids
    }

    nonisolated static func image(for id: String, size: CGSize) async -> UIImage? {
        guard let asset = asset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true          // photos stockées sur iCloud
        options.deliveryMode = .highQualityFormat      // un seul retour
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    nonisolated static func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = asset(id) else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    /// Poids réel sur le téléphone (photo + vidéo des Live Photos + retouches).
    nonisolated static func fileSize(for id: String) -> Int64 {
        guard let asset = asset(id) else { return 0 }
        var total: Int64 = 0
        for resource in PHAssetResource.assetResources(for: asset) {
            if let n = resource.value(forKey: "fileSize") as? NSNumber {
                total += n.int64Value
            }
        }
        return total
    }

    // MARK: Modifications

    nonisolated static func createAlbum(named title: String) async throws -> String? {
        let box = ValueBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            box.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        return box.value
    }

    nonisolated static func add(_ ids: [String], toAlbum albumID: String) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard
                let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
                let request = PHAssetCollectionChangeRequest(for: album)
            else { return }
            request.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    nonisolated static func remove(_ ids: [String], fromAlbum albumID: String) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard
                let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
                let request = PHAssetCollectionChangeRequest(for: album)
            else { return }
            request.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    nonisolated static func setFavorite(_ id: String, _ value: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
            PHAssetChangeRequest(for: asset).isFavorite = value
        }
    }

    /// Supprime pour de vrai. iOS affiche sa propre confirmation,
    /// et les éléments restent 30 jours dans « Supprimés récemment ».
    nonisolated static func delete(_ ids: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }
}
