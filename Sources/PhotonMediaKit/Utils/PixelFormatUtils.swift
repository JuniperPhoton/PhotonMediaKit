//
//  File.swift
//  
//
//  Created by Photon Juniper on 2024/3/23.
//

import Foundation
import Metal
import CoreVideo

class PixelFormatUtils {
    public static let shared = PixelFormatUtils()
    
    private init() {
        // empty
    }
    
    public func getMetalFormatForDepth(cvPixelFormat: OSType) -> MTLPixelFormat? {
        if cvPixelFormat == kCVPixelFormatType_DisparityFloat16 || cvPixelFormat == kCVPixelFormatType_DepthFloat16 {
            return .r16Float
        }
        
        if cvPixelFormat == kCVPixelFormatType_DisparityFloat32 || cvPixelFormat == kCVPixelFormatType_DepthFloat32 {
            return .r32Float
        }
        
        return nil
    }
}
