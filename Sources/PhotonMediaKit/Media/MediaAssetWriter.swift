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

public struct EditedOutput {
    public let file: URL
    public let data: PHAdjustmentData
    
    public init(file: URL, data: PHAdjustmentData) {
        self.file = file
        self.data = data
    }
}

public class MediaAssetWriter {
    struct AccessError: Error {
        // empty
    }
    
    public static func getCacheDir() -> URL? {
        guard let cacheDir = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            print("error on create cache url for file")
            return nil
        }
        
        return cacheDir
    }
    
    public static let shared = MediaAssetWriter()
    
    /// Check if the readWrite permission is denied.
    @available(*, deprecated, renamed: "isDeniedForReadWrite", message: "Use isDeniedForReadWrite instead.")
    public var isDenied: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .denied || status == .restricted
    }
    
    /// Check if the readWrite permission is authorized.
    @available(*, deprecated, renamed: "isAuthorizedForReadWrite", message: "Use isAuthorizedForReadWrite instead.")
    public var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }
    
    /// Check if the readWrite permission is denied.
    public var isDeniedForReadWrite: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .denied || status == .restricted
    }
    
    /// Check if the readWrite permission is denied.
    public var isDeniedForAddOnly: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .denied || status == .restricted
    }
    
    /// Check if the readWrite permission is authorized.
    public var isAuthorizedForReadWrite: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }
    
    /// Check if the addOnly permission is authorized.
    public var isAuthorizedForAddOnly: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }
    
    private init() {
        // private
    }
    
    /// Request for authorization for a specific level.
    /// - parameter level: The ``PHAccessLevel`` level to request.
    public func requestForPermission(for level: PHAccessLevel = .readWrite) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: level)
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
    @discardableResult
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
    @discardableResult
    public func saveMediaFileToPhotoLibrary(
        rawURL: URL,
        processedURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation?,
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
    @discardableResult
    public func saveMediaFileToPhotoLibrary(
        rawURL: URL,
        processedURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation?,
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
                
                placeholder = creationRequest.placeholderForCreatedAsset
            } completionHandler: { success, error in
                print("save media result: \(success) error: \(String(describing: error))")
                
                if deleteOnComplete {
                    if let processedURL = processedURL {
                        try? FileManager.default.removeItem(at: processedURL.absoluteURL)
                    }
                    try? FileManager.default.removeItem(at: rawURL.absoluteURL)
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
    @discardableResult
    public func saveMediaFileToAlbum(
        processedURL: URL,
        rawURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation?,
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
    /// - parameter editedOutput: The edited version of it.
    /// - parameter rawURL: The backed RAW file if presented
    /// - parameter collection: The ``PHAssetCollection`` to be added into
    /// - parameter location: The ``CLLocation`` of this photo asset
    /// - parameter deleteOnComplete: Whether deleting the files or not after complete(success or fail)
    @discardableResult
    public func saveMediaFileToPhotoLibrary(
        processedURL: URL,
        editedOutput: EditedOutput? = nil,
        rawURL: URL? = nil,
        livePhotoMovieURL: URL? = nil,
        collection: PHAssetCollection? = nil,
        location: CLLocation?,
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
                
                if let livePhotoMovieURL = livePhotoMovieURL {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = deleteOnComplete
                    creationRequest.addResource(with: .pairedVideo, fileURL: livePhotoMovieURL, options: options)
                }
                
                placeholder = creationRequest.placeholderForCreatedAsset
                
                if let placeholder = placeholder, let editedOutput = editedOutput {
                    let editOutput = PHContentEditingOutput(placeholderForCreatedAsset: placeholder)
                    editOutput.adjustmentData = editedOutput.data
                    let renderURL = editOutput.renderedContentURL
                    
                    do {
                        try FileManager.default.copyItem(at: editedOutput.file, to: renderURL)
                        creationRequest.contentEditingOutput = editOutput
                    } catch {
                        LibLogger.libDefault.error("error on copying edited output file to render url \(renderURL)")
                    }
                }
                
                collection?.addAsset(creation: creationRequest)
            } completionHandler: { success, error in
                LibLogger.libDefault.log("save media result: \(success) error: \(String(describing: error))")
                
                if deleteOnComplete {
                    if let rawURL = rawURL {
                        try? FileManager.default.removeItem(at: rawURL.absoluteURL)
                    }
                    
                    if let livePhotoMovieURL = livePhotoMovieURL {
                        try? FileManager.default.removeItem(at: livePhotoMovieURL.absoluteURL)
                    }
                    
                    try? FileManager.default.removeItem(at: processedURL.absoluteURL)
                    
                    if let edited = editedOutput?.file {
                        try? FileManager.default.removeItem(at: edited)
                    }
                }
                
                continuation.resume(returning: placeholder?.localIdentifier)
            }
        }
    }
    
    @discardableResult
    public func saveMediaFileToAlbum(
        file: URL,
        collection: PHAssetCollection? = nil,
        location: CLLocation?,
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
                    try? FileManager.default.removeItem(at: file.absoluteURL)
                }
                
                continuation.resume(returning: success)
            }
        }
    }
    
    @discardableResult
    public func addMediaAssetToAlbum(
        asset: PHAsset,
        collection: PHAssetCollection
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                collection.addAsset(asset: asset)
            } completionHandler: { success, error in
                continuation.resume(returning: success)
            }
        }
    }
    
    /// Edit the ``PHAsset`` and provide the edited version of it.
    ///
    /// Note that on iOS 16, this will show a prompt to let the user allow the modification. To avoid this issue
    /// when saving new photo using PhotoKit, you should use ``saveMediaFileToPhotoLibrary(processedURL:editedOutput:rawURL:collection:location:deleteOnComplete:)``
    /// with ``editedOutput`` parameter provided.
    ///
    /// - parameter asset: The asset to be edited.
    /// - parameter editedFileURL: The JPEG file URL for the edited version of it. Note that this MUST be JPEG.
    /// If it's editing LivePhoto with non nil ``PHLivePhotoFrameProcessingBlock``, this must be nil due to the reason that the still image is also
    /// processed in ``PHLivePhotoFrameProcessingBlock``.
    ///
    /// - parameter data: The ``PHAdjustmentData`` describing the changes.
    ///
    /// To provideEditedVersion for LivePhoto, use ``provideEditedVersionForLivePhoto(asset:livePhotoFrameProcessor:data:deleteOnComplete:)``.
    public func provideEditedVersion(
        asset: PHAsset,
        editedFileURL: URL,
        data: PHAdjustmentData,
        deleteOnComplete: Bool
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: nil) { input, _ in
                guard let input = input else {
                    continuation.resume(returning: false)
                    return
                }
                
                let output = PHContentEditingOutput(contentEditingInput: input)
                output.adjustmentData = data
                
                do {
                    // For iOS 17.0, we can use renderedContentURL(for type: UTType) to use other UTType other than JPEG.
                    // But for now we don't support this yet.
                    let renderURL = output.renderedContentURL
                    try FileManager.default.copyItem(at: editedFileURL, to: renderURL)
                    
                    PHPhotoLibrary.shared().performChanges {
                        let changed = PHAssetChangeRequest(for: asset)
                        changed.contentEditingOutput = output
                    } completionHandler: { success, error in
                        if !success {
                            LibLogger.libDefault.error("failed to perform changed for PHAsset, error: \(error)")
                        }
                        
                        if deleteOnComplete {
                            try? FileManager.default.removeItem(at: editedFileURL)
                        }
                        continuation.resume(returning: success)
                    }
                } catch {
                    continuation.resume(returning: false)
                    LibLogger.libDefault.error("error copying item \(error)")
                }
            }
        }
    }
    
    /// Edit the ``PHAsset`` that's is a Live Photo and provide the edited version of it.
    ///
    /// - parameter asset: The asset to be edited.
    /// - parameter data: The ``PHAdjustmentData`` describing the changes.
    /// - parameter version: Which version to be loaded to edit.
    /// - parameter livePhotoFrameProcessor: The block to process each frame of the Live Photo still image and video.
    ///
    /// NOTE: Editing the "current" version may not work if there is an edited version of it, which may due to the system issue.
    public func provideEditedVersionForLivePhoto(
        asset: PHAsset,
        data: PHAdjustmentData,
        version: MediaAssetVersion,
        livePhotoFrameProcessor: @escaping PHLivePhotoFrameProcessingBlock
    ) async -> Bool {
        return await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: .create(version: version)) { input, _ in
                guard let input = input, input.livePhoto != nil else {
                    continuation.resume(returning: false)
                    return
                }
                
                if let context = PHLivePhotoEditingContext(livePhotoEditingInput: input) {
                    context.frameProcessor = livePhotoFrameProcessor
                    
                    let output = PHContentEditingOutput(contentEditingInput: input)
                    output.adjustmentData = data
                    
                    context.saveLivePhoto(to: output) { success, error in
                        PHPhotoLibrary.shared().performChanges {
                            let changed = PHAssetChangeRequest(for: asset)
                            changed.contentEditingOutput = output
                        } completionHandler: { success, error in
                            if !success {
                                LibLogger.libDefault.error("failed to perform changed for PHAsset, error: \(error)")
                            }
                            continuation.resume(returning: success)
                        }
                    }
                } else {
                    continuation.resume(returning: false)
                }
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
    
    public func createTempFileToSave(rootDir: URL? = getCacheDir(), originalFilename: String, utType: UTType) -> URL? {
        guard let extensions = utType.preferredFilenameExtension else {
            print("error on getting preferredFilenameExtension")
            return nil
        }
        return createTempFileToSave(rootDir: rootDir, originalFilename: originalFilename, extensions: extensions)
    }
    
    public func createTempFileToSave(
        rootDir: URL? = getCacheDir() ,
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
    
    @discardableResult
    func addAsset(asset: PHAsset) -> Bool {
        guard let request = PHAssetCollectionChangeRequest(for: self) else {
            return false
        }
        
        request.addAssets([asset] as NSArray)
        
        return true
    }
}

extension PHContentEditingInputRequestOptions {
    static func create(version: MediaAssetVersion) -> PHContentEditingInputRequestOptions {
        switch version {
        case .current:
            return .createForEditedVersion()
        case .original:
            return .createForOriginalVersion()
        }
    }
    
    static func createForOriginalVersion() -> PHContentEditingInputRequestOptions {
        let options = PHContentEditingInputRequestOptions()
        options.canHandleAdjustmentData = { _ in
            return true
        }
        options.isNetworkAccessAllowed = true
        return options
    }
    
    static func createForEditedVersion() -> PHContentEditingInputRequestOptions {
        let options = PHContentEditingInputRequestOptions()
        options.canHandleAdjustmentData = { _ in
            return false
        }
        options.isNetworkAccessAllowed = true
        return options
    }
}
