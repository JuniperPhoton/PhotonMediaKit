//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/6/18.
//

import Foundation
import Photos

public extension PHAsset {
    /// Get the pixel size of this PHAsset.
    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }
    
    /// Check if this PHAsset has RAW resources.
    /// This method could take time. To get better performance, try cache the result.
    func hasRAWResources() -> Bool {
        let resources = PHAssetResource.assetResources(for: self)
        let rawRes = resources.first { res in
            if let utType = UTType(res.uniformTypeIdentifier) {
                return utType.isRawImage()
            } else {
                return false
            }
        }
        return rawRes != nil
    }
    
    /// Check if this PHAsset is a sub type of LivePhoto.
    func isLivePhotoSubType() -> Bool {
        let subType = UInt(self.mediaSubtypes.rawValue)
        return (subType & UInt(PHAssetMediaSubtype.photoLive.rawValue)) != 0
    }
    
    /// Check if this PHAsset is a sub type of photoDepthEffect.
    func isDepthEffectPhotoSubType() -> Bool {
        let subType = UInt(self.mediaSubtypes.rawValue)
        return (subType & UInt(PHAssetMediaSubtype.photoDepthEffect.rawValue)) != 0
    }
}
