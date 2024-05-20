//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/23.
//

import Foundation
import Metal
import CoreVideo
import CoreImage

public class PixelFormatUtils {
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
    
    public static func convertPixelBuffer(
        sourceBuffer: CVPixelBuffer,
        format: OSType = kCVPixelFormatType_32BGRA,
        context: CIContext = CIContext()
    ) -> CVPixelBuffer? {
        // Define the attributes for the destination pixel buffer
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: CVPixelBufferGetWidth(sourceBuffer),
            kCVPixelBufferHeightKey as String: CVPixelBufferGetHeight(sourceBuffer),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        // Create a pixel buffer pool
        var pixelBufferPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelBufferPool)
        guard status == kCVReturnSuccess, let pool = pixelBufferPool else {
            print("Error: Could not create pixel buffer pool")
            return nil
        }
        
        // Create a pixel buffer from the pool
        var dstPixelBuffer: CVPixelBuffer?
        let createStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dstPixelBuffer)
        guard createStatus == kCVReturnSuccess, let destinationBuffer = dstPixelBuffer else {
            print("Error: Could not create destination pixel buffer")
            return nil
        }
        
        // Create a Core Image context
        let ciContext = context
        
        // Create a CIImage from the source pixel buffer
        let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
        
        // Render the CIImage into the destination pixel buffer
        ciContext.render(sourceImage, to: destinationBuffer)
        
        return destinationBuffer
    }
}
