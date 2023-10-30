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
    
    func getPHImageRequestOptionsVersion() -> PHImageRequestOptionsVersion {
        switch self {
        case .original: return .original
        case .current: return .current
        }
    }
    
    func getPHVideoRequestOptionsVersion() -> PHVideoRequestOptionsVersion {
        switch self {
        case .current:
            return .current
        case .original:
            return .original
        }
    }
    
    public var description: String {
        return self.rawValue
    }
}
