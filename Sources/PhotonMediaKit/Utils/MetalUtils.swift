//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/23.
//

import Foundation
import CoreVideo
import CoreMedia

public class MetalUtils {
    public static let shared = MetalUtils()
    
    private init() {
        // empty
    }
    
    func allocateOutputBuffers(
        with formatDescription: CMFormatDescription,
        outputRetainedBufferCountHint: Int
    ) -> CVPixelBufferPool? {
        let inputDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let outputPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(inputDimensions.width),
            kCVPixelBufferHeightKey as String: Int(inputDimensions.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: outputRetainedBufferCountHint]
        var cvPixelBufferPool: CVPixelBufferPool?
        // Create a pixel buffer pool with the same pixel attributes as the input format description
        CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                poolAttributes as NSDictionary?,
                                outputPixelBufferAttributes as NSDictionary?,
                                &cvPixelBufferPool)
        guard let pixelBufferPool = cvPixelBufferPool else {
            print("Allocation failure: Could not create pixel buffer pool")
            return nil
        }
        return pixelBufferPool
    }
    
    func makeTextureFromCVPixelBuffer(
        pixelBuffer: CVPixelBuffer,
        textureFormat: MTLPixelFormat,
        textureCache: CVMetalTextureCache
    ) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Create a Metal texture from the image buffer
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            textureFormat,
            width,
            height,
            0,
            &cvTextureOut
        )
        
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Depth converter failed to create preview texture of texture format \(textureFormat), size: \(width)x\(height)")
            
            CVMetalTextureCacheFlush(textureCache, 0)
            
            return nil
        }
        
        return texture
    }
}
