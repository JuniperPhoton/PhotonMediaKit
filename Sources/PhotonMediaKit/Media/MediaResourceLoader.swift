//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/12/24.
//

import Foundation
import Photos

public class MediaResourceLoader {
    public static let shared = MediaResourceLoader()
    
    private init() {
        // empty
    }
    
    public func loadAssetResourcesAsync(
        for asset: PHAsset,
        for types: [UTType]
    ) async -> PHAssetResource? {
        loadAssetResources(for: asset, for: types)
    }
    
    public func loadAssetResources(
        for asset: PHAsset,
        for types: [UTType]
    ) -> PHAssetResource? {
        let res = PHAssetResource.assetResources(for: asset)
        return res.first { resource in
            let uniformTypeIdentifier = resource.uniformTypeIdentifier
            guard let utType = UTType(uniformTypeIdentifier) else {
                return false
            }
            if types.contains(utType) {
                return true
            }
            return types.first { superType in
                utType.isSubtype(of: superType)
            } != nil
        }
    }
}
