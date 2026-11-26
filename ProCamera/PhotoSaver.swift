import Photos
import UIKit

/// 照片归档 —— 对应 Android 版 domain 层的 PhotoSaver：
/// 拍完的照片/录像统一存入系统相册，并归档到名为 "ProCamera" 的相簿
/// （Android 版对应 Pictures/ProCamera 目录）。
enum PhotoSaver {
    static let albumName = "ProCamera"

    static func savePhoto(data: Data, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                completion?(false)
                return
            }
            fetchOrCreateAlbum { album in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                    if let album = album,
                       let placeholder = request.placeholderForCreatedAsset,
                       let albumChange = PHAssetCollectionChangeRequest(for: album) {
                        albumChange.addAssets([placeholder] as NSArray)
                    }
                }, completionHandler: { ok, _ in
                    completion?(ok)
                })
            }
        }
    }

    static func saveVideo(fileURL: URL, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                completion?(false)
                return
            }
            fetchOrCreateAlbum { album in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .video, fileURL: fileURL, options: nil)
                    if let album = album,
                       let placeholder = request.placeholderForCreatedAsset,
                       let albumChange = PHAssetCollectionChangeRequest(for: album) {
                        albumChange.addAssets([placeholder] as NSArray)
                    }
                }, completionHandler: { ok, _ in
                    completion?(ok)
                })
            }
        }
    }

    private static func fetchOrCreateAlbum(completion: @escaping (PHAssetCollection?) -> Void) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        if let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: options
        ).firstObject {
            completion(existing)
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
        }, completionHandler: { _, _ in
            let created = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: options
            ).firstObject
            completion(created)
        })
    }
}
