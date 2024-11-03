//
//  ConvertVersion.swift
//  MyerTidy (iOS)
//
//  Created by Photon Juniper on 2023/1/7.
//

import Foundation
import Photos

public enum MediaAssetVersion: String, Hashable, CaseIterable, CustomStringConvertible {
    case current = "MediaAssetVersionCurrent"
    case original = "MediaAssetVersionOriginal"
    
    public func getPHImageRequestOptionsVersion() -> PHImageRequestOptionsVersion {
        switch self {
        case .original: return .original
        case .current: return .current
        }
    }
    
    public func getPHVideoRequestOptionsVersion() -> PHVideoRequestOptionsVersion {
        switch self {
        case .current:
            return .current
        case .original:
            return .original
        }
    }
    
    func getPHLivePhotoRequestOptionsTypes() -> [PHAssetResourceType] {
        switch self {
        case .current:
            // fullSizePairedVideo: Provides the current video data component of a Live Photo asset.
            // pairedVideo: Provides the original video data component of a Live Photo asset.
            // Note that if a LivePhoto has never been edited, there is no such PHAssetResource that matches .fullSizePairedVideo.
            return [.fullSizePairedVideo, .pairedVideo]
        case .original:
            return [.pairedVideo]
        }
    }
    
    public var description: String {
        return self.rawValue
    }
}
