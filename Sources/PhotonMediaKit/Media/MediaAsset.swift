//
//  File.swift
//  
//
//  Created by Photon Juniper on 2023/10/30.
//
import Foundation
import Photos

public var byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
}()

public protocol MediaAssetProvider: Equatable {
    var phAssetRes: MediaAssetRes { get }
    func updateCurrentAsset() async
}

/// Contains a ``PHAsset`` and a dedicated ``PHAssetResource``.
/// You use a the ``phAsset`` to fetch image to display, or use ``res`` to retrieve information about the resource.
public struct MediaAssetRes {
    public let phAsset: PHAsset
    public var resource: PHAssetResource?
    
    public init(phAsset: PHAsset, resource: PHAssetResource? = nil) {
        self.phAsset = phAsset
        self.resource = resource
    }
    
    public var isVideo: Bool {
        phAsset.mediaType == .video
    }
    
    public var size: Int64? {
        var sizeOnDisk: Int64? = 0
        
        if let resource = self.resource,
           let unsignedInt64 = resource.value(forKey: "fileSize") as? CLong {
            sizeOnDisk = Int64(bitPattern: UInt64(unsignedInt64))
        }
        
        guard let sizeOnDisk = sizeOnDisk else {
            return 0
        }
        
        if sizeOnDisk == 0 {
            return nil
        }
        
        return sizeOnDisk
    }
    
    public var readableSize: String {
        let sizeOnDisk: Int64? = size
        
        guard let sizeOnDisk = sizeOnDisk else {
            return ""
        }
        
        if sizeOnDisk == 0 {
            return ""
        }
        
        return converByteToHumanReadable(sizeOnDisk)
    }
    
    private func converByteToHumanReadable(_ bytes:Int64) -> String {
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }
}

extension MediaAssetRes: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(phAsset)
    }
}
