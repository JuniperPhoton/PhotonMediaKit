//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/18.
//

import Foundation
import CoreImage

/// Represent the types of all supported auxiliary data.
///
/// To access the key from CGImage framework, use ``cgImageKey`` property.
public enum AuxiliaryDataType: CaseIterable {
    case hdrGainMap
    case isoGainMap
    case depth
    case disparity
    case portraitEffectsMatte
    
    public var cgImageKey: CFString {
        switch self {
        case .isoGainMap:
            if #available(iOS 18.0, macOS 15.0, *) {
                return kCGImageAuxiliaryDataTypeISOGainMap
            } else {
                return "kCGImageAuxiliaryDataTypeISOGainMap" as CFString
            }
        case .hdrGainMap:
            return kCGImageAuxiliaryDataTypeHDRGainMap
        case .depth:
            return kCGImageAuxiliaryDataTypeDepth
        case .disparity:
            return kCGImageAuxiliaryDataTypeDisparity
        case .portraitEffectsMatte:
            return kCGImageAuxiliaryDataTypePortraitEffectsMatte
        }
    }
}
