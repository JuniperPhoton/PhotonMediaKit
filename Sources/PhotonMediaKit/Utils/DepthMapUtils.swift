//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/23.
//

import Foundation
import AVFoundation
import CoreImage

public struct ColorWithComponents {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat
}

/// Provides utility methods for depth map.
public class DepthMapUtils {
    public static let shared = DepthMapUtils()
    
    public static let supportedFormats = [
        kCVPixelFormatType_DisparityFloat16,
        kCVPixelFormatType_DisparityFloat32,
        kCVPixelFormatType_DepthFloat16,
        kCVPixelFormatType_DepthFloat32
    ]
    
    private init() {
        // empty
    }
    
    public func isPixelFormatSupported(_ format: OSType) -> Bool {
        return DepthMapUtils.supportedFormats.contains(format)
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
    
    /// Get the pixel value of the buffer, given a x and y position.
    /// - parameter bgra32GrayscaleBuffer: The ``CVPixelBuffer`` which is in the format of ``kCVPixelFormatType_32BGRA``.
    public func getPixelValue(from bgra32GrayscaleBuffer: CVPixelBuffer, atX x: Int, y: Int) -> ColorWithComponents? {
        let width = CVPixelBufferGetWidth(bgra32GrayscaleBuffer)
        let height = CVPixelBufferGetHeight(bgra32GrayscaleBuffer)
        
        // Check if the coordinates are within the pixel buffer bounds
        guard x >= 0, x < width, y >= 0, y < height else {
            return nil
        }
        
        let format = CVPixelBufferGetPixelFormatType(bgra32GrayscaleBuffer)
        if format != kCVPixelFormatType_32BGRA {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(bgra32GrayscaleBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(bgra32GrayscaleBuffer, .readOnly) }
        
        // Get the base address of the pixel buffer
        guard let baseAddress = CVPixelBufferGetBaseAddress(bgra32GrayscaleBuffer) else {
            return nil
        }
        
        // Calculate the byte-per-row value for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(bgra32GrayscaleBuffer)
        
        // Calculate the byte offset for the (x, y) coordinate
        let byteOffset = (bytesPerRow * y) + (x * 4) // 4 bytes per pixel for BGRA
        
        // Get the pixel data
        let pixelData = baseAddress.advanced(by: byteOffset).assumingMemoryBound(to: UInt8.self)
        
        // Extract the BGRA components
        let blue = CGFloat(pixelData[0]) / 255.0
        let green = CGFloat(pixelData[1]) / 255.0
        let red = CGFloat(pixelData[2]) / 255.0
        let alpha = CGFloat(pixelData[3]) / 255.0
        
        return ColorWithComponents(red: red, green: green, blue: blue, alpha: alpha)
    }
}
