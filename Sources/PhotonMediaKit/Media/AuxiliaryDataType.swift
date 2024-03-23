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
    case depth
    case disparity
    case portraitEffectsMatte
    
    public var cgImageKey: CFString {
        switch self {
        case .hdrGainMap:
            kCGImageAuxiliaryDataTypeHDRGainMap
        case .depth:
            kCGImageAuxiliaryDataTypeDepth
        case .disparity:
            kCGImageAuxiliaryDataTypeDisparity
        case .portraitEffectsMatte:
            kCGImageAuxiliaryDataTypePortraitEffectsMatte
        }
    }
}
