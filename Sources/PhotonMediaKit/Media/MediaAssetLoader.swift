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

public struct PHFetchTracableResult {
    public let result: PHFetchResult<PHAsset>?
    public var assetRes: [MediaAssetRes]
    
    init(_ result: PHFetchResult<PHAsset>?, _ assetRes: [MediaAssetRes]) {
        self.result = result
        self.assetRes = assetRes
    }
}

/// Use this class to help you fetch media from PhotoKit and load the data of the assets.
public actor MediaAssetLoader {
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
    
    public init() {
        // empty
    }
    
#if canImport(UIKit)
    /// Fetch ``UIImage`` from ``PHAsset``.
    @available(iOS 15.0, *)
    public func fetchUIImage(
        phAsset: PHAsset,
        option: FetchOption,
        version: MediaAssetVersion,
        useDynamicRange: Bool
    ) async -> UIImage? {
        LibLogger.mediaLoader.log("fetchUIImage for \(phAsset.localIdentifier), option \(option), version: \(version)")
        switch option {
        case .thumbnail:
            return await fetchThumbnailUIImage(phAsset: phAsset)
        case .full:
            return await fetchFullUIImage(phAsset: phAsset, version: version, useDynamicRange: useDynamicRange)
        case .size(w: let w, h: let h):
            return await fetchThumbnailUIImage(phAsset: phAsset,
                                               size: CGSize(width: w, height: h))
        }
    }
    
    /// Fetch resized ``UIImage`` from ``PHAsset``.
    @available(iOS 15.0, *)
    public func fetchThumbnailUIImage(
        phAsset: PHAsset,
        size: CGSize = CGSize(width: 400, height: 400)
    ) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.isSynchronous = true
            
            let id = cacheManager.requestImage(for: phAsset, targetSize: size,
                                               contentMode: .aspectFit, options: o) { uiImage, map in
                continuation.resume(returning: uiImage)
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
        useDynamicRange: Bool
    ) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.isSynchronous = true
            o.version = version.getPHImageRequestOptionsVersion()
            
            let id = cacheManager.requestImageDataAndOrientation(for: phAsset, options: o) { data, _, _, _ in
                let image = UIImageReaderCompat(useDynamicRange: useDynamicRange).uiImage(data: data)
                continuation.resume(returning: image)
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
        onProgressChanged: @escaping (Double) -> Void
    ) async -> (Data?, CGImagePropertyOrientation) {
        return await withCheckedContinuation { continuation in
            let manager = PHImageManager()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = allowFromNetwork
            o.isSynchronous = true
            if allowFromNetwork {
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
        size: CGSize = CGSize(width: 400, height: 400),
        isNetworkAccessAllowed: Bool = false,
        onProgressChanged: ((Double) -> Void)? = nil
    ) async -> CGImage? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = isNetworkAccessAllowed
            o.isSynchronous = true
            o.resizeMode = .fast
            
            if isNetworkAccessAllowed {
                o.progressHandler = { progress, error, obj, map in
                    onProgressChanged?(progress)
                }
            }
            
            cacheManager.requestImage(for: phAsset,
                                      targetSize: size,
                                      contentMode: .aspectFit,
                                      options: o) { platformImage, data in
#if os(macOS)
                continuation.resume(returning: platformImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
#else
                continuation.resume(returning: platformImage?.cgImage)
#endif
            }
        }
    }
    
    public func requestAVAsset(
        phAsset: PHAsset,
        version: MediaAssetVersion,
        isNetworkAccessAllowed: Bool,
        onProgressChanged: @escaping (Double) -> Void
    ) async -> AVAsset? {
        return await withCheckedContinuation { continuation in
            let cacheManager = PHCachingImageManager.default()
            
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = isNetworkAccessAllowed
            o.version = version.getPHVideoRequestOptionsVersion()
            
            if isNetworkAccessAllowed {
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
        configure: ((PHFetchOptions) -> Void)? = nil
    ) async -> PHFetchTracableResult? {
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
        
        let sizePredicate = NSPredicate(format: "pixelWidth > 1920 || pixelHeight > 1920")
        
        let allVideosOptions = PHFetchOptions()
        allVideosOptions.sortDescriptors = sortOption.asSortDescriptors()
        allVideosOptions.predicate = NSCompoundPredicate(
            type: .and,
            subpredicates: [favoritesPredicate, creationPredicate, sizePredicate].compactMap { $0 }
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
        
        return PHFetchTracableResult(allVideos, rawVideos)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchPhoto(itemIdentifier: String) async -> PHAsset? {
        return await fetchPhotosByCollection(
            dateRange: Date.distantPast...Date.distantFuture,
            collection: nil,
            loadAssetResourcesInPlaceTypes: []
        ) { options in
            options.fetchLimit = 1
            options.predicate = NSPredicate(format: "localIdentifier == %@", itemIdentifier)
        }?.result?.firstObject
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchPhotosByCollection(
        dateRange: ClosedRange<Date>,
        collection: PHAssetCollection?,
        loadAssetResourcesInPlaceTypes: [UTType],
        sortOption: FetchSortOption = .creationDate(ascending: false),
        favoritedOptions: FavoritedFilterOptions = .all,
        configure: ((PHFetchOptions) -> Void)? = nil
    ) async -> PHFetchTracableResult? {
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
        
        return PHFetchTracableResult(allPhotos, rawImages)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func fetchRawPhotosBySmartCollection(
        dateRange: ClosedRange<Date>,
        loadAssetResourcesInPlace: Bool,
        configure: ((PHFetchOptions) -> Void)? = nil
    ) async -> PHFetchTracableResult? {
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
