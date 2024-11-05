//
//  MediaAssetCachedLoader.swift
//  PhotonMediaKit
//
//  Created by JuniperPhoton on 2024/11/4.
//
import Foundation
import CoreGraphics

public protocol CacheDirProvider {
    func cacheDir() -> URL?
}

public protocol CacheKeyProvider {
    func cacheKey(phAsset: MediaAssetRes, version: MediaAssetVersion, size: CGSize) -> String
}

public class DefaultCacheDirProvider: CacheDirProvider {
    public init() {}
    
    public func cacheDir() -> URL? {
        guard let cacheDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        do {
            let dir = cacheDir.appendingPathComponent("MediaAssetCachedLoader")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }
}

public class DefaultCacheKeyProvider: CacheKeyProvider {
    public init() {}
    
    public func cacheKey(phAsset: MediaAssetRes, version: MediaAssetVersion, size: CGSize) -> String {
        guard let id = phAsset.phAsset.localIdentifier.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return ""
        }
        return "\(id)_\(version.rawValue)_\(Int(size.width))x\(Int(size.height))"
    }
}

public class MediaAssetCachedLoader {
    public static func createDefaultInstance() -> MediaAssetCachedLoader {
        return MediaAssetCachedLoader(
            dirProvider: DefaultCacheDirProvider(),
            cacheKeyProvider: DefaultCacheKeyProvider()
        )
    }
    
    public let dirProvider: CacheDirProvider
    public let cacheKeyProvider: CacheKeyProvider
    
    private let loader = MediaAssetLoader()
    private let queue = DispatchQueue(label: "media_cache_queue", qos: .utility)
    
    public init(dirProvider: CacheDirProvider, cacheKeyProvider: CacheKeyProvider) {
        self.dirProvider = dirProvider
        self.cacheKeyProvider = cacheKeyProvider
    }
    
    public func fetchThumbnailCGImage(
        assestRes: MediaAssetRes,
        version: MediaAssetVersion,
        isNetworkAccessAllowed: Bool = false,
        size: CGSize = MediaAssetLoader.defaultThumbnailSize
    ) async -> CGImage? {
        let key = cacheKeyProvider.cacheKey(phAsset: assestRes, version: version, size: size)
        let dir = dirProvider.cacheDir()
        guard let cachedFile = dir?.appendingPathComponent(key, conformingTo: .jpeg) else {
            return nil
        }
        
        if let cgImage = await tryFetchThumbnailCGImageFromFile(file: cachedFile) {
            return cgImage
        }
        
        if let cgImage = await loader.fetchThumbnailCGImage(
            phAsset: assestRes.phAsset,
            size: size,
            version: version,
            isNetworkAccessAllowed: isNetworkAccessAllowed
        ) {
            queue.async { [weak self] in
                guard let self else { return }
                saveThumbnailCGImageToFile(cgImage: cgImage, file: cachedFile)
            }
            
            return cgImage
        } else {
            return nil
        }
    }
    
    private func tryFetchThumbnailCGImageFromFile(file: URL) async -> CGImage? {
        if !FileManager.default.fileExists(atPath: file.path) {
            return nil
        }
        
        guard let data = try? Data(contentsOf: file) else {
            return nil
        }
        
        return try? await CGImageIO.shared.loadCGImage(data: data)
    }
    
    @discardableResult
    private func saveThumbnailCGImageToFile(cgImage: CGImage, file: URL) -> Bool {
        do {
            let data = try CGImageIO.shared.getJpegDataNonIsolated(cgImage: cgImage)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            print("saveThumbnailCGImageToFile error \(error)")
            return false
        }
    }
}
