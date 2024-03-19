//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/18.
//

import Foundation
import CoreImage

public enum AuxiliaryDataType: CaseIterable {
    case hdrGainMap
    case depth
    case disparity
    case portraitEffectsMatte
    
    var cgImageKey: CFString {
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
