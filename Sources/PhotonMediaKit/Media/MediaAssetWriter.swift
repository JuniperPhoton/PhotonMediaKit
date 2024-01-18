//
//  AppPhotoLibrary.swift
//  MyerTidy
//
//  Created by Photon Juniper on 2023/1/16.
//

import Foundation
import Photos
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

public class MediaAssetWriter {
    struct AccessError: Error {
        // empty
    }
    
    public static let shared = MediaAssetWriter()
    
    public var isDenied: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .denied || status == .restricted
    }
    
    public var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }
    
    private init() {
        // private
    }
    
    public func requestForPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if status == .authorized || status == .limited {
            return true
        }
        return false
    }
    
    public func createOrGetCollection(title: String) async -> PHAssetCollection? {
        let getCollection = {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", title)
            
            return PHAssetCollection
                .fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
                .firstObject
        }
        
        return await withCheckedContinuation { continuation in
            if let collection = getCollection() {
                continuation.resume(returning: collection)
            } else {
                PHPhotoLibrary.shared().performChanges {
                    let _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                } completionHandler: { success, error in
                    if success, let collection = getCollection() {
                        continuation.resume(returning: collection)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
#if os(iOS)
    public func saveImageToAlbum(
        uiImage: UIImage,
        collection: PHAssetCollection? = nil
    ) async throws -> Bool {
        if !(await requestForPermission()) {
            throw AccessError()
        }
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.creationRequestForAsset(from: uiImage)
                collection?.addAsset(creation: creation)
            } completionHandler: { success, error in
                continuation.resume(returning: success)
            }
        }
    }
#endif
    
    /// Save the RAW file to photo library and return the result.
    /// - parameter rawURL: The main RAW file if presented
    /// - parameter processedURL: The optional photo image for this asset
    /// - parameter collection: The ``PHAssetCollection`` to be added into
    /// - parameter location: The ``CLLocation`` of this photo asset
    /// - parameter deleteOnComplete: Whether deleting the files or not after complete(success or fail)
    public func saveMediaFileToPhotoLibrary(
        rawURL: URL,
        processedURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation? = nil,
        deleteOnComplete: Bool
    ) async -> Bool {
        return await saveMediaFileToPhotoLibrary(
            rawURL: rawURL,
            processedURL: processedURL,
            collection: collection,
            location: location,
            deleteOnComplete: deleteOnComplete
        ) != nil
    }
    
    /// Save the RAW file to photo library and return the localIdentifier if succeeded.
    /// - parameter rawURL: The main RAW file if presented
    /// - parameter processedURL: The optional photo image for this asset
    /// - parameter collection: The ``PHAssetCollection`` to be added into
    /// - parameter location: The ``CLLocation`` of this photo asset
    /// - parameter deleteOnComplete: Whether deleting the files or not after complete(success or fail)
    public func saveMediaFileToPhotoLibrary(
        rawURL: URL,
        processedURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation? = nil,
        deleteOnComplete: Bool
    ) async -> String? {
        return await withCheckedContinuation { continuation in
            print("saveMediaFileToAlbum, main of rawURL, processedURL: \(String(describing: processedURL))")
            
            var placeholder: PHObjectPlaceholder? = nil
            
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.location = location
                
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = deleteOnComplete
                creationRequest.addResource(
                    with: .photo,
                    fileURL: rawURL,
                    options: options
                )
                
                if let processedURL = processedURL {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = deleteOnComplete
                    creationRequest.addResource(
                        with: .alternatePhoto,
                        fileURL: processedURL,
                        options: options
                    )
                }
                
                collection?.addAsset(creation: creationRequest)
            } completionHandler: { success, error in
                print("save media result: \(success) error: \(String(describing: error))")
                
                if deleteOnComplete {
                    do {
                        if let processedURL = processedURL {
                            try FileManager.default.removeItem(at: processedURL.absoluteURL)
                        }
                        try FileManager.default.removeItem(at: rawURL.absoluteURL)
                    } catch {
                        // ignored
                    }
                }
                
                continuation.resume(returning: placeholder?.localIdentifier)
            }
        }
    }
    
    /// Save the media file to photo library and return the result.
    /// - parameter processedURL: The main photo image for this asset
    /// - parameter rawURL: The backed RAW file if presented
    /// - parameter collection: The ``PHAssetCollection`` to be added into
    /// - parameter location: The ``CLLocation`` of this photo asset
    /// - parameter deleteOnComplete: Whether deleting the files or not after complete(success or fail)
    public func saveMediaFileToAlbum(
        processedURL: URL,
        rawURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation? = nil,
        deleteOnComplete: Bool
    ) async -> Bool {
        return await saveMediaFileToPhotoLibrary(
            processedURL: processedURL,
            rawURL: rawURL,
            collection: collection,
            location: location,
            deleteOnComplete: deleteOnComplete
        ) != nil
    }
    
    /// Save the media file to photo library and return the localIdentifier if succeeded.
    /// - parameter processedURL: The main photo image for this asset
    /// - parameter rawURL: The backed RAW file if presented
    /// - parameter collection: The ``PHAssetCollection`` to be added into
    /// - parameter location: The ``CLLocation`` of this photo asset
    /// - parameter deleteOnComplete: Whether deleting the files or not after complete(success or fail)
    public func saveMediaFileToPhotoLibrary(
        processedURL: URL,
        rawURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation? = nil,
        deleteOnComplete: Bool
    ) async -> String? {
        return await withCheckedContinuation { continuation in
            LibLogger.libDefault.log("saveMediaFileToAlbum, main of processedURL, raw: \(String(describing: rawURL))")
            
            var placeholder: PHObjectPlaceholder? = nil
            
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.location = location
                
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = deleteOnComplete
                creationRequest.addResource(
                    with: .photo,
                    fileURL: processedURL,
                    options: options
                )
                
                if let rawURL = rawURL {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = deleteOnComplete
                    creationRequest.addResource(
                        with: .alternatePhoto,
                        fileURL: rawURL,
                        options: options
                    )
                }
                
                placeholder = creationRequest.placeholderForCreatedAsset
                
                collection?.addAsset(creation: creationRequest)
            } completionHandler: { success, error in
                LibLogger.libDefault.log("save media result: \(success) error: \(String(describing: error))")
                
                if deleteOnComplete {
                    do {
                        if let rawURL = rawURL {
                            try FileManager.default.removeItem(at: rawURL.absoluteURL)
                        }
                        try FileManager.default.removeItem(at: processedURL.absoluteURL)
                    } catch {
                        // ignored
                    }
                }
                
                continuation.resume(returning: placeholder?.localIdentifier)
            }
        }
    }
    
    public func saveMediaFileToAlbum(
        file: URL,
        collection: PHAssetCollection? = nil,
        location: CLLocation? = nil,
        deleteOnComplete: Bool
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                if file.isImage() {
                    if let creation = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: file.absoluteURL) {
                        creation.location = location
                        collection?.addAsset(creation: creation)
                    }
                } else {
                    if let creation = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: file.absoluteURL) {
                        creation.location = location
                        collection?.addAsset(creation: creation)
                    }
                }
            } completionHandler: { success, error in
                LibLogger.libDefault.log("save media result: \(success) error: \(String(describing: error)), deleteOnComplete: \(deleteOnComplete)")
                
                if deleteOnComplete {
                    do {
                        try FileManager.default.removeItem(at: file.absoluteURL)
                    } catch {
                        print("error on delete \(file.absoluteURL), \(error)")
                    }
                }
                
                continuation.resume(returning: success)
            }
        }
    }
    
    public func delete(asset: PHAsset) async -> Bool {
        return await delete(assets: [asset])
    }
    
    public func delete(assets: [PHAsset]) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let _ = PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                continuation.resume(returning: success)
            }
        }
    }
    
    public func favorite(asset: PHAsset) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = true
            } completionHandler: { success, error in
                continuation.resume(returning: success)
            }
        }
    }
    
    public func createTempFileToSave(originalFilename: String, utType: UTType) -> URL? {
        guard let extensions = utType.preferredFilenameExtension else {
            print("error on getting preferredFilenameExtension")
            return nil
        }
        return createTempFileToSave(originalFilename: originalFilename, extensions: extensions)
    }
    
    public func createTempFileToSave(
        originalFilename: String,
        subDirName: String? = nil,
        extensions: String
    ) -> URL? {
        guard var cacheDir = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            print("error on create cache url for file")
            return nil
        }
        
        if let subDirName = subDirName,
           let dir = URL(string: "\(cacheDir.absoluteString)\(subDirName)/") {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                cacheDir = dir
            } catch {
                return nil
            }
        }
        
        guard let name = NSString(string: originalFilename).deletingPathExtension
            .addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) else {
            print("createTempFileToSave failed for name \(originalFilename)")
            return nil
        }
        
        let fileName = name  + "." + extensions
        
        let url = URL(string: "\(cacheDir.absoluteString)\(fileName)")
        
        if let url = url, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        
        return url
    }
}

fileprivate extension PHAssetCollection {
    @discardableResult
    func addAsset(creation: PHAssetCreationRequest) -> Bool {
        guard let request = PHAssetCollectionChangeRequest(for: self) else {
            return false
        }
        
        guard let placeholder = creation.placeholderForCreatedAsset else {
            return false
        }
        
        request.addAssets([placeholder] as NSArray)
        
        return true
    }
}
