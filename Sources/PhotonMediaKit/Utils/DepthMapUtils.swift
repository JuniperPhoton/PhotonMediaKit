//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/23.
//

import Foundation
import AVFoundation
import CoreImage

/// Provides utility methods for depth map.
public class DepthMapUtils {
    public static let shared = DepthMapUtils()
    
    static let supportedFormats = [
        kCVPixelFormatType_DisparityFloat16,
        kCVPixelFormatType_DisparityFloat32,
        kCVPixelFormatType_DepthFloat16,
        kCVPixelFormatType_DepthFloat32
    ]
    
    private init() {
        // empty
    }
    
    /// Create ``AVDepthData`` from a disparity ``CIImage``.
    ///
    /// - parameter ciContext: The ``CIContext`` instance to use.
    /// If this method is called frequently, you should consider reusing this ``CIContext``.
    ///
    /// - parameter grayscaleImage: The ``CIImage`` containing the grayscale image,
    /// which should has the pixel format of ``kCVPixelFormatType_32BGRA``.
    ///
    /// - parameter originalDepthData: The original ``AVDepthData``.
    /// If it's not nil, this method will utilize it to replace underlaying depth map.
    /// If it's nil, this method will create a new ``AVDepthData``.
    public func createAVDepthData(
        ciContext: CIContext = CIContext(),
        grayscaleImage: CIImage,
        originalDepthData: AVDepthData?
    ) -> AVDepthData? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey as String: kCFBooleanTrue!
        ] as CFDictionary
        
        let scaled = grayscaleImage.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        
        // The size of the pixel buffer should match the size of the CIImage
        let width = scaled.extent.width
        let height = scaled.extent.height
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(width),
            Int(height),
            kCVPixelFormatType_32BGRA, // todo try support more formats
            attributes,
            &pixelBuffer
        )
        
        guard let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        // Render CIImage to CVPixelBuffer
        ciContext.render(scaled, to: pixelBuffer)
        
        let targetPixelFormat = kCVPixelFormatType_DisparityFloat16
        
        let converter = GrayscaleToDepthConverter()
        converter.prepare()
        let depthPixelBuffer = converter.render(
            input: pixelBuffer,
            targetCVPixelFormat: targetPixelFormat
        )
        
        guard let depthPixelBuffer = depthPixelBuffer else {
            return nil
        }
        
        if let originalDepthData = originalDepthData {
            do {
                return try originalDepthData.replacingDepthDataMap(with: depthPixelBuffer)
            } catch {
                LibLogger.depthMap.error("error on replacingDepthDataMap \(error)")
                return nil
            }
        } else {
            return createAVDepthData(
                depthPixelBuffer: depthPixelBuffer,
                cvPixelFormat: targetPixelFormat
            )
        }
    }
    
    /// Create ``AVDepthData`` from ``CVPixelBuffer``.
    /// - parameter depthPixelBuffer: The instance of ``CVPixelBuffer``. Should contain disparity or depth data.
    ///
    /// - parameter cvPixelFormat: Should be the following formats:
    /// kCVPixelFormatType_DisparityFloat16
    /// kCVPixelFormatType_DisparityFloat32
    /// kCVPixelFormatType_DepthFloat16
    /// kCVPixelFormatType_DepthFloat32
    public func createAVDepthData(depthPixelBuffer: CVPixelBuffer, cvPixelFormat: OSType) -> AVDepthData? {
        let supportedFormats = [
            kCVPixelFormatType_DisparityFloat16,
            kCVPixelFormatType_DisparityFloat32,
            kCVPixelFormatType_DepthFloat16,
            kCVPixelFormatType_DepthFloat32
        ]
        
        if !supportedFormats.contains(cvPixelFormat) {
            LibLogger.depthMap.error("cvPixelFormat not supported: \(cvPixelFormat)")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        defer {
            CVPixelBufferUnlockBaseAddress(depthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)
        let totalBytes = bytesPerRow * CVPixelBufferGetHeight(depthPixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else {
            return nil
        }
        
        guard let data = CFDataCreate(
            kCFAllocatorDefault,
            baseAddress.assumingMemoryBound(to: UInt8.self),
            totalBytes
        ) else {
            return nil
        }
        
        var metadata: Dictionary<CFString, Any> = Dictionary()
        metadata[kCGImagePropertyPixelFormat] = cvPixelFormat
        metadata[kCGImagePropertyWidth] = width
        metadata[kCGImagePropertyHeight] = height
        metadata[kCGImagePropertyBytesPerRow] = bytesPerRow
        
        // Now create AVDepthData from the pixel buffer
        var depthData: AVDepthData?
        
        do {
            // Create AVDepthData from the depth data map
            depthData = try AVDepthData(fromDictionaryRepresentation: [
                kCGImageAuxiliaryDataInfoData: data,
                kCGImageAuxiliaryDataInfoDataDescription: metadata
            ])
        } catch {
            LibLogger.depthMap.error("Error on creating AVDepthData: \(error)")
        }
        
        return depthData
    }
}
