//
//  PhotosManager.swift
//  MyerTidy
//
//  Created by Photon Juniper on 2023/1/4.
//

import Foundation
import Photos
import PhotonUtility

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

public struct PHFetchTraceableResult {
    public let result: PHFetchResult<PHAsset>?
    public var assetRes: [MediaAssetRes]
    
    init(_ result: PHFetchResult<PHAsset>?, _ assetRes: [MediaAssetRes]) {
        self.result = result
        self.assetRes = assetRes
    }
}

/// Use this class to help you fetch media from PhotoKit and load the data of the assets.
public actor MediaAssetLoader {
    public static let defaultThumbnailSize = CGSize(width: 400, height: 400)
    
    public enum FetchOption: Equatable, CustomStringConvertible {
        case thumbnail
        case full
        case size(w: CGFloat, h: CGFloat)
        
        public var description: String {
            switch self {
            case .full: return "full"
            case .thumbnail: return "thumbnail"
            case .size(let w, let h): return "size \(w)x\(h)"
            }
        }
    }
    
    public enum FetchSortOption {
        case creationDate(ascending: Bool)
        case modificationDate(ascending: Bool)
        case systemDefault
        
        public func asSortDescriptors() -> [NSSortDescriptor] {
            switch self {
            case .creationDate(let ascending):
                return [NSSortDescriptor(key: "creationDate", ascending: ascending)]
            case .modificationDate(let ascending):
                return [NSSortDescriptor(key: "modificationDate", ascending: ascending)]
            case .systemDefault:
                return []
            }
        }
    }
    
    public enum FetchSizeOption {
        case none
        case atLeastOneGreaterThan(width: CGFloat, height: CGFloat)
        case bothGreaterThan(width: CGFloat, height: CGFloat)
        
        public static var greaterThan1080P: FetchSizeOption {
            FetchSizeOption.atLeastOneGreaterThan(width: 1920, height: 1920)
        }
        
        public func asNSPredicate() -> NSPredicate {
            let sizePredicate: NSPredicate
            switch self {
            case .none:
                sizePredicate = NSPredicate(format: "pixelWidth > 0 && pixelHeight > 0")
            case .atLeastOneGreaterThan(let width, let height):
                sizePredicate = NSPredicate(format: "pixelWidth > \(width) || pixelHeight > \(height)")
            case .bothGreaterThan(let width, let height):
                sizePredicate = NSPredicate(format: "pixelWidth > \(width) && pixelHeight > \(height)")
            }
            return sizePredicate
        }
    }
    
    public struct FetchError: Error {
        let message: String
    }
    
    private struct FetchResult<T> {
        let result: T?
    }
    
    public init() {
        // empty
    }
    
    /// Fetch the first ``PHAssetResource`` which matches the order of ``orderedResTypes``.
    ///
    /// - parameter phAsset: The ``PHAsset`` that contains the ``PHAssetResource``.
    /// - parameter orderedResTypes: The ordered ``PHAssetResourceType`` to match.
    ///
    /// For example, given a orderedResTypes of [PHAssetResourceType.photo, PHAssetResourceType.video],
    /// if a ``PHAssetResource`` of ``PHAssetResourceType.photo`` exists, it will be returned,
    /// otherwise it will continue to find a ``PHAssetResource`` of ``PHAssetResourceType.video``.
    public func getFirstMatchedResType(
        phAsset: PHAsset,
        orderedResTypes: [PHAssetResourceType]
    ) async -> PHAssetResource? {
        var resultRes: PHAssetResource? = nil
        
        let allRes = PHAssetResource.assetResources(for: phAsset)
        
        for type in orderedResTypes {
            resultRes = allRes.first { res in res.type == type}
            if resultRes != nil {
                break
            }
        }
        
        return resultRes
    }
    
    /// Fetch the data of the Live Photo movie in a ``PHAsset`` and write the data into the file URL you provide.
    public func fetchLivePhotoMovieURL(
        phAsset: PHAsset,
        version: MediaAssetVersion,
        toFile: URL,
        allowFromNetwork: Bool,
        onProgressChanged: ((Double) -> Void)? = nil
    ) async -> URL? {
        guard let livePhotoRes = await getFirstMatchedResType(
            phAsset: phAsset,
            orderedResTypes: version.getPHLivePhotoRequestOptionsTypes()
        ) else {
            LibLogger.mediaLoader.error("failed to find live photo res")
            return nil
        }
        
        let manager = PHAssetResourceManager.default()
        
        let requestOptions = PHAssetResourceRequestOptions()
        requestOptions.isNetworkAccessAllowed = allowFromNetwork
        
        if allowFromNetwork, let onProgressChanged = onProgressChanged {
            requestOptions.progressHandler = { progress in
                onProgressChanged(progress)
            }
        }
        
        do {
            try await manager.writeData(for: livePhotoRes, toFile: toFile, options: requestOptions)
            return toFile
        } catch {
            LibLogger.mediaLoader.error("error on writeData \(error)")
            return nil
        }
    }
    
    /// Fetch the ``PHLivePhoto`` object of the ``PHAsset``.
    public func fetchLivePhoto(
        phAsset: PHAsset,
        version: MediaAssetVersion,
        allowFromNetwork: Bool,
        onProgressChanged: ((Double) -> Void)? = nil
    ) async -> PHLivePhoto? {
        return await withCheckedContinuation { continuation in
            let manager = PHImageManager()
            
            let o = PHLivePhotoRequestOptions()
            o.isNetworkAccessAllowed = allowFromNetwork
            
            if allowFromNetwork, let onProgressChanged = onProgressChanged {
                o.progressHandler = { progress, error, obj, map in
                    onProgressChanged(progress)
                }
            }
            
            o.version = version.getPHImageRequestOptionsVersion()
            
            LibLogger.mediaLoader.log("begin fetch PHLivePhoto for \(phAsset.localIdentifier)")
            
            let id = manager.requestLivePhoto(
                for: phAsset,
                targetSize: CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight),
                contentMode: .aspectFit,
                options: o
            ) { photo, dic in
                if (dic?[PHImageResultIsDegradedKey] as? Bool) == true {
                    return
                } else {
                    continuation.resume(returning: photo)
                }
            }
            if Task.isCancelled {
                manager.cancelImageRequest(id)
            }
        }
    }
    
#if canImport(UIKit)
    /// Fetch ``UIImage`` from ``PHAsset``.
    @available(iOS 15.0, *)
    public func fetchUIImage(
        phAsset: PHAsset,
        option: FetchOption,
        version: MediaAssetVersion,
        prefersHighDynamicRange: Bool
    ) async -> UIImage? {
        LibLogger.mediaLoader.log("fetchUIImage for \(phAsset.localIdentifier), option \(option), version: \(version)")
        switch option {
        case .thumbnail:
            return await fetchThumbnailUIImage(phAsset: phAsset)
        case .full:
            return await fetchFullUIImage(
                phAsset: phAsset,
                version: version,
                prefersHighDynamicRange: prefersHighDynamicRange
            )
        case .size(w: let w, h: let h):
            return await fetchThumbnailUIImage(
                phAsset: phAsset,
                size: CGSize(width: w, height: h)
            )
        }
    }
    
    /// Fetch resized ``UIImage`` from ``PHAsset``.
    @available(iOS 15.0, *)
    public func fetchThumbnailUIImage(
        phAsset: PHAsset,
        version: MediaAssetVersion = .current,
        isNetworkAccessAllowed: Bool = false,
        size: CGSize = MediaAssetLoader.defaultThumbnailSize
    ) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = isNetworkAccessAllowed
            o.isSynchronous = true
            o.resizeMode = .fast
            o.version = version.getPHImageRequestOptionsVersion()
            
            let id = cacheManager.requestImage(
                for: phAsset,
                targetSize: size,
                contentMode: .aspectFit,
                options: o
            ) { uiImage, _ in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: uiImage)
                }
            }
            
            if Task.isCancelled {
                cacheManager.cancelImageRequest(id)
            }
        }
    }
    
    /// Fetch full-sized ``UIImage`` from ``PHAsset``.
    @available(iOS 15.0, tvOS 15.0, *)
    public func fetchFullUIImage(
        phAsset: PHAsset,
        version: MediaAssetVersion,
        prefersHighDynamicRange: Bool
    ) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.isSynchronous = true
            o.version = version.getPHImageRequestOptionsVersion()
            
            let id = cacheManager.requestImageDataAndOrientation(for: phAsset, options: o) { data, _, _, metadata in
                guard let data = data else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Not until iOS 18 the UIImageReader have resolved memory leak issue.
                if #available(iOS 18.0, *) {
                    var config = UIImageReader.Configuration()
                    config.prefersHighDynamicRange = prefersHighDynamicRange
                    config.preparesImagesForDisplay = true
                    
                    let width = phAsset.pixelWidth
                    let height = phAsset.pixelHeight
                    config.preferredThumbnailSize = CGSize(width: width, height: height)
                    
                    let reader = UIImageReader(configuration: config)
                    let uiImage = reader.image(data: data)
                    
                    if Task.isCancelled {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: uiImage)
                    }
                } else {
                    if Task.isCancelled {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: UIImage(data: data))
                    }
                }
            }
            
            if Task.isCancelled {
                cacheManager.cancelImageRequest(id)
            }
        }
    }
#endif
    
    public func fetchFullCGImage(phAsset: PHAsset) async -> CGImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = false
            o.isSynchronous = true
            
            let id = cacheManager
                .requestImageDataAndOrientation(for: phAsset, options: o) { data, str, orientation, map in
                    if let data = data,
                       let source = CGImageSourceCreateWithData(data as CFData, nil) {
                        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
                        continuation.resume(returning: cgImage)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            
            if Task.isCancelled {
                cacheManager.cancelImageRequest(id)
            }
        }
    }
    
    public func fetchFullRawData(phAsset: PHAsset) async -> (PHAssetResource, Data)? {
        return await withCheckedContinuation { continuation in
            guard let rawRes = MediaResourceLoader.shared.loadAssetResources(for: phAsset, for: [.rawImage]) else {
                continuation.resume(returning: nil)
                return
            }
            
            let option = PHAssetResourceRequestOptions()
            option.isNetworkAccessAllowed = false
            
            var outputData = Data()
            
            PHAssetResourceManager.default().requestData(
                for: rawRes,
                options: option
            ) { data in
                outputData.append(data)
            } completionHandler: { error in
                if error != nil && outputData.count > 0 {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: (rawRes, outputData))
                }
            }
        }
    }
    
    public func fetchFullData(
        phAsset: PHAsset,
        version: MediaAssetVersion,
        allowFromNetwork: Bool,
        onProgressChanged: ((Double) -> Void)? = nil
    ) async -> (Data?, CGImagePropertyOrientation) {
        return await withCheckedContinuation { continuation in
            let manager = PHImageManager()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = allowFromNetwork
            o.isSynchronous = true
            if allowFromNetwork, let onProgressChanged = onProgressChanged {
                o.progressHandler = { progress, error, obj, map in
                    onProgressChanged(progress)
                }
            }
            o.version = version.getPHImageRequestOptionsVersion()
            
            LibLogger.mediaLoader.log("begin fetch full data for \(phAsset.localIdentifier)")
            
            let id = manager
                .requestImageDataAndOrientation(for: phAsset, options: o) { data, str, orientation, map in
                    LibLogger.mediaLoader.log("end fetch full data for \(phAsset.localIdentifier)")
                    continuation.resume(returning: (data, orientation))
                }
            if Task.isCancelled {
                manager.cancelImageRequest(id)
            }
        }
    }
    
    public func fetchThumbnailCGImage(
        phAsset: PHAsset,
        size: CGSize = MediaAssetLoader.defaultThumbnailSize,
        isNetworkAccessAllowed: Bool = false,
        onProgressChanged: ((Double) -> Void)? = nil
    ) async -> CGImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = isNetworkAccessAllowed
            o.isSynchronous = true
            o.resizeMode = .fast
            
            if isNetworkAccessAllowed, let onProgressChanged = onProgressChanged {
                o.progressHandler = { progress, error, obj, map in
                    onProgressChanged(progress)
                }
            }
            
            let id = cacheManager.requestImage(
                for: phAsset,
                targetSize: size,
                contentMode: .aspectFit,
                options: o
            ) { platformImage, data in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
#if os(macOS)
                    continuation.resume(returning: platformImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
#else
                    continuation.resume(returning: platformImage?.cgImage)
#endif
                }
            }
            
            if Task.isCancelled {
                cacheManager.cancelImageRequest(id)
            }
        }
    }
    
    public func fetchProperties(phAsset: PHAsset) async -> Dictionary<String, Any>? {
        let (data, _) = await fetchFullData(phAsset: phAsset, version: .current, allowFromNetwork: false, onProgressChanged: { _ in })
        if let data = data {
            return await CGImageIO.shared.getProperties(data: data)
        } else {
            return nil
        }
    }
    
    public func requestAVAsset(
        phAsset: PHAsset,
        version: MediaAssetVersion,
        isNetworkAccessAllowed: Bool,
        onProgressChanged: ((Double) -> Void)? = nil
    ) async -> AVAsset? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = isNetworkAccessAllowed
            o.version = version.getPHVideoRequestOptionsVersion()
            
            if isNetworkAccessAllowed, let onProgressChanged = onProgressChanged {
                o.progressHandler = { progress, error, obj, map in
                    onProgressChanged(progress)
                }
            }
            
            cacheManager.requestAVAsset(forVideo: phAsset, options: o) { avAsset, _, map in
                guard let asset = avAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: asset)
            }
        }
    }
    
    public func fetchVideos(
        dateRange: ClosedRange<Date>,
        filterOptions: MediaFilterOptions,
        sortOption: FetchSortOption = .creationDate(ascending: false),
        sizeOption: FetchSizeOption = FetchSizeOption.greaterThan1080P,
        configure: ((PHFetchOptions) -> Void)? = nil
    ) async -> PHFetchTraceableResult? {
        let fromDate = dateRange.lowerBound
        let toDate = dateRange.upperBound
        
        let options = PHFetchOptions()
        
        LibLogger.mediaLoader.log("begin fetch video collections from \(fromDate) to \(toDate)")
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumVideos, options: options)
        
        LibLogger.mediaLoader.log("end fetch video collections, count \(collections.count)")
        
        guard let videoCollection = collections.firstObject else {
            return nil
        }
        
        let favoritesPredicate: NSPredicate?
        switch filterOptions.favoritedOptions {
        case .all:
            favoritesPredicate = nil
        case .favorited:
            favoritesPredicate = NSPredicate(format: "isFavorite == %@", argumentArray: [NSNumber(booleanLiteral: true)])
        case .nonFavorited:
            favoritesPredicate = NSPredicate(format: "isFavorite == %@", argumentArray: [NSNumber(booleanLiteral: false)])
        }
        
        let creationPredicate = NSPredicate(
            format: "creationDate >= %@ && creationDate <= %@",
            argumentArray: [fromDate, toDate]
        )
        
        let allVideosOptions = PHFetchOptions()
        allVideosOptions.sortDescriptors = sortOption.asSortDescriptors()
        allVideosOptions.predicate = NSCompoundPredicate(
            type: .and,
            subpredicates: [favoritesPredicate, creationPredicate, sizeOption.asNSPredicate()].compactMap { $0 }
        )
        
        if let configure = configure {
            configure(allVideosOptions)
        }
        
        let allVideos = PHAsset.fetchAssets(in: videoCollection, options: allVideosOptions)
        
        LibLogger.mediaLoader.log("begin enumerateObjects all videos")
        
        var rawVideos = fetchAssetWithRes(
            allPhotos: allVideos,
            loadAssetResourcesInPlaceTypes: [.video, .movie]
        )
        
        if filterOptions.isFilterOn {
            rawVideos = rawVideos.filter { asset in
                filterOptions.isSizeMeet(asset.size) && filterOptions.isDurationMeet(asset.phAsset.duration)
            }
        }
        
        LibLogger.mediaLoader.log("end enumerateObjects all videos \(rawVideos.count)")
        
        return PHFetchTraceableResult(allVideos, rawVideos)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchPHAsset(
        itemIdentifier: String,
        collection: PHAssetCollection? = nil,
        predicates: [NSPredicate] = []
    ) async -> PHAsset? {
        var compoundPredicates = predicates
        compoundPredicates.append(NSPredicate(format: "localIdentifier == %@", itemIdentifier))
        
        return await fetchPhotosByCollection(
            dateRange: Date.distantPast...Date.distantFuture,
            collection: collection,
            loadAssetResourcesInPlaceTypes: []
        ) { options in
            options.fetchLimit = 1
            options.predicate = NSCompoundPredicate(
                type: .and,
                subpredicates: compoundPredicates
            )
        }?.result?.firstObject
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchPHAssets(
        itemIdentifiers: [String],
        collection: PHAssetCollection? = nil,
        predicates: [NSPredicate] = []
    ) async -> PHFetchTraceableResult? {
        var compoundPredicates = predicates
        compoundPredicates.append(NSPredicate(format: "localIdentifier in %@", itemIdentifiers))
        
        return await fetchPhotosByCollection(
            dateRange: Date.distantPast...Date.distantFuture,
            collection: collection,
            loadAssetResourcesInPlaceTypes: []
        ) { options in
            options.predicate = NSCompoundPredicate(
                type: .and,
                subpredicates: compoundPredicates
            )
        }
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchPhotosByCollection(
        dateRange: ClosedRange<Date>,
        collection: PHAssetCollection?,
        loadAssetResourcesInPlaceTypes: [UTType],
        sortOption: FetchSortOption = .creationDate(ascending: false),
        favoritedOptions: FavoritedFilterOptions = .all,
        configure: ((PHFetchOptions) -> Void)? = nil
    ) async -> PHFetchTraceableResult? {
        let fromDate = dateRange.lowerBound
        let toDate = dateRange.upperBound
        
        let favoritesPredicate: NSPredicate?
        switch favoritedOptions {
        case .all:
            favoritesPredicate = nil
        case .favorited:
            favoritesPredicate = NSPredicate(format: "isFavorite == %@", argumentArray: [NSNumber(booleanLiteral: true)])
        case .nonFavorited:
            favoritesPredicate = NSPredicate(format: "isFavorite == %@", argumentArray: [NSNumber(booleanLiteral: false)])
        }
        
        let creationPredicate = NSPredicate(
            format: "creationDate >= %@ && creationDate <= %@",
            argumentArray: [fromDate, toDate]
        )
        
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = sortOption.asSortDescriptors()
        allPhotosOptions.predicate = NSCompoundPredicate(
            type: .and,
            subpredicates: [favoritesPredicate, creationPredicate].compactMap { $0 }
        )
        
        if let configure = configure {
            configure(allPhotosOptions)
        }
        
        let allPhotos: PHFetchResult<PHAsset>
        if let collection = collection {
            allPhotos = PHAsset.fetchAssets(in: collection, options: allPhotosOptions)
        } else {
            allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        }
        
        LibLogger.mediaLoader.log("begin enumerateObjects all photos")
        
        let rawImages = fetchAssetWithRes(
            allPhotos: allPhotos,
            loadAssetResourcesInPlaceTypes: loadAssetResourcesInPlaceTypes
        )
        
        LibLogger.mediaLoader.log("end enumerateObjects all photos \(rawImages.count)")
        
        return PHFetchTraceableResult(allPhotos, rawImages)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchRawPhotosBySmartCollection(
        dateRange: ClosedRange<Date>,
        loadAssetResourcesInPlace: Bool,
        favoritedOptions: FavoritedFilterOptions = .all,
        configure: ((PHFetchOptions) -> Void)? = nil
    ) async -> PHFetchTraceableResult? {
        let options = PHFetchOptions()
        
        LibLogger.mediaLoader.log("begin fetch raw collections from \(dateRange)")
        
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumRAW,
            options: options
        )
        
        LibLogger.mediaLoader.log("end fetch raw collections, count \(collections.count)")
        
        guard let rawCollection = collections.firstObject else {
            return nil
        }
        
        return await fetchPhotosByCollection(
            dateRange: dateRange,
            collection: rawCollection,
            loadAssetResourcesInPlaceTypes: [],
            favoritedOptions: favoritedOptions,
            configure: configure
        )
    }
    
    private func fetchAssetWithRes(
        allPhotos: PHFetchResult<PHAsset>,
        loadAssetResourcesInPlaceTypes: [UTType]
    ) -> [MediaAssetRes] {
        var results: [MediaAssetRes] = []
        
        LibLogger.mediaLoader.log("begin enumerateObjects all photos \(allPhotos.count), forUTTypes \(String(describing: loadAssetResourcesInPlaceTypes.joinToString()))")
        
        allPhotos.enumerateObjects { asset, i, stop in
            if !Task.isCancelled {
                if !loadAssetResourcesInPlaceTypes.isEmpty {
                    let res = MediaResourceLoader.shared.loadAssetResources(for: asset,
                                                                            for: loadAssetResourcesInPlaceTypes)
                    if let nonNilRes = res {
                        results.append(MediaAssetRes(phAsset: asset, resource: nonNilRes))
                    }
                } else {
                    results.append(MediaAssetRes(phAsset: asset, resource: nil))
                }
            } else {
                LibLogger.mediaLoader.log("cancel on fetching photos, setting stop to true")
                stop.pointee = true
            }
        }
        
        if Task.isCancelled {
            return []
        }
        
        return results
    }
}
