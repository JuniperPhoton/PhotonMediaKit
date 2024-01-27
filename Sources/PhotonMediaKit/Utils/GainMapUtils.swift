//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/1/25.
//

import Foundation
import CoreImage

public struct GainMapAuxiliaryData {
    public let gainMapImageData: Data
    public let desc: Dictionary<String, Any>
    
    init(gainMapImageData: Data, desc: Dictionary<String, Any>) {
        self.gainMapImageData = gainMapImageData
        self.desc = desc
    }
}

public struct GainmainAuxiliaryTransformationResult {
    public let ciImage: CIImage
    public let desc: Dictionary<String, Any>
    
    public init(ciImage: CIImage, desc: Dictionary<String, Any>) {
        self.ciImage = ciImage
        self.desc = desc
    }
}

public struct GainMapInfo {
    /// The width of the gain map image.
    public let width: Int
    
    /// The height of the gain map image.
    public let height: Int
    
    /// The bytesPerRow of the gain map image.
    public let bytesPerRow: Int
    
    /// The pixelFormat of the gain map image.
    public let pixelFormat: Int32
    
    /// The orientation of the gain map image in the ``CGImagePropertyOrientation``.
    public let orientation: CGImagePropertyOrientation
    
    /// If the metadata contains the headroom, this will not be nil.
    /// Otherwise, you should read the headroom from maker.
    public let headroom: CGFloat?
    
    /// The image bitmap data of the gain map image.
    public let data: Data
    
    /// Convenient way to create the ``CIImage`` of this gain map.
    public func toCIImage() -> CIImage? {
        return CIImage(
            bitmapData: data,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: height),
            format: .L8,
            colorSpace: nil
        )
    }
}

public class GainMapUtils {
    public static let keyWidth = "Width"
    public static let keyHeight = "Height"
    public static let keyBytesPerRow = "BytesPerRow"
    public static let keyOrientation = "Orientation"
    
    private static var keyHDRGainMapHeadroom = "HDRGainMapHeadroom"
    private static var keyHDRGainMapVersion = "HDRGainMapVersion"
    
    public static let shared = GainMapUtils()
    
    public func updateData(
        auxiliaryMap: Dictionary<CFString, Any>,
        transformed: GainMapAuxiliaryData
    ) async -> Dictionary<CFString, Any> {
        var mutable = auxiliaryMap
        mutable[kCGImageAuxiliaryDataInfoData] = transformed.gainMapImageData
        mutable[kCGImageAuxiliaryDataInfoDataDescription] = transformed.desc
        return mutable
    }
    
    /// Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public func extractHDRGainMap(url: URL) async -> GainMapInfo? {
        let _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        return await extractGainMap(data: data)
    }
    
    /// Extract the HDR gain map original data and parse as ``CFDictionary``.
    public func extractGainMapDictionary(data: Data) async -> CFDictionary? {
        let options: [String: Any] = [
            kCGImageSourceShouldCacheImmediately as String: false,
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        
        guard let auxiliaryData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) else {
            return nil
        }
        
        return auxiliaryData
    }
    
    /// Extract the gain map size.
    public func extractGainMapSize(auxiliaryMap: Dictionary<CFString, Any>) async -> CGSize? {
        guard let desc = auxiliaryMap[kCGImageAuxiliaryDataInfoDataDescription] as? Dictionary<String, Any> else {
            return nil
        }
        
        guard let width = desc["Width"] as? Int,
              let height = desc["Height"] as? Int
        else {
            return nil
        }
        
        return CGSize(width: width, height: height)
    }
    
    /// Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public func extractGainMap(data: Data) async -> GainMapInfo? {
        guard let auxiliaryMap = await extractGainMapDictionary(data: data) as? Dictionary<CFString, Any> else {
            return nil
        }
        
        if let desc = auxiliaryMap[kCGImageAuxiliaryDataInfoDataDescription] as? Dictionary<String, Any>,
           let metadata = auxiliaryMap[kCGImageAuxiliaryDataInfoMetadata],
           let data = auxiliaryMap[kCGImageAuxiliaryDataInfoData] as? Data {
            
            guard let width = desc["Width"] as? Int,
                  let height = desc["Height"] as? Int,
                  let bytesPerRow = desc["BytesPerRow"] as? Int,
                  let pixelFormat = desc["PixelFormat"] as? Int32
            else {
                return nil
            }
            
            let orientation = desc["Orientation"] as? Int32 ?? 0
            let cgOrientation = CGImagePropertyOrientation(rawValue: UInt32(orientation)) ?? .up
            
            let cgMetadata = metadata as! CGImageMetadata
            var gainMapHeadroom: CGFloat? = nil
            var valid = false
            if let tags = CGImageMetadataCopyTags(cgMetadata) as? Array<Any> {
                for tag in tags {
                    let cfTag = tag as! CGImageMetadataTag
                    let name = CGImageMetadataTagCopyName(cfTag) as? String
                    let value = CGImageMetadataTagCopyValue(cfTag)
                    if name == GainMapUtils.keyHDRGainMapHeadroom, let value = value as? String, let float = Float(value) {
                        gainMapHeadroom = CGFloat(float)
                    }
                    
                    if name == GainMapUtils.keyHDRGainMapVersion {
                        valid = true
                    }
                }
            }
            
            if !valid {
                return nil
            }
            
            debugPrint("extractHDRGainMap desc is \(desc)")
            debugPrint("extractHDRGainMap metadata is \(metadata)")
            
            return GainMapInfo(
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                pixelFormat: pixelFormat,
                orientation: cgOrientation,
                headroom: gainMapHeadroom,
                data: data
            )
        }
        
        return nil
    }
    
    /// Crop the gain map image to the specified ``CGRect`` and return the result with corrected desc.
    /// - parameter ciContext: The ``CIContext`` to perform render. It will be better to cache the same ciContext object for later use.
    /// - parameter auxiliaryMap: The gain map root data, retrieved by ``EDRUtils.extractHDRGainMapDictionary``.
    public func cropGainMap(
        ciContext: CIContext,
        auxiliaryMap: Dictionary<CFString, Any>,
        rect: CGRect
    ) async -> GainMapAuxiliaryData? {
        return await applyTransformation(ciContext: ciContext, auxiliaryMap: auxiliaryMap) { ciImage, desc in
            var cropped = ciImage.cropped(to: rect)
            cropped = cropped.transformed(
                by: CGAffineTransform.init(
                    translationX: -cropped.extent.minX,
                    y: -cropped.extent.minY
                )
            )
            
            var mutableDesc = desc
            mutableDesc[GainMapUtils.keyWidth] = cropped.extent.width
            mutableDesc[GainMapUtils.keyHeight] = cropped.extent.height
            mutableDesc[GainMapUtils.keyBytesPerRow] = cropped.extent.width
            
            return GainmainAuxiliaryTransformationResult(ciImage: cropped, desc: mutableDesc)
        }
    }
    
    /// Read the ``CGImagePropertyOrientation`` from the desc map and rotate the auxiliary image based on the orientation
    /// and update the width, height and orientation of the desc and return the new one.
    /// - parameter ciContext: The ``CIContext`` to perform render. It will be better to cache the same ciContext object for later use.
    /// - parameter auxiliaryMap: The gain map root data, retrieved by ``EDRUtils.extractHDRGainMapDictionary``.
    ///
    /// To know more about the struct of auxiliaryData, please refer to: https://developer.apple.com/documentation/avfoundation/avdepthdata/creating_auxiliary_depth_data_manually?changes=_2_9
    ///
    /// Note that the ``AVDepthData`` class can't create with auxiliaryData of gain map.
    ///
    /// Warning: For some reason, when shooting with 48MP and using this method to apply orientation to the gain map,
    /// the system's Photos app will fail to render the image when applying zoom-in.
    public func applyingExifOrientation(
        ciContext: CIContext,
        auxiliaryMap: Dictionary<CFString, Any>
    ) async -> GainMapAuxiliaryData? {
        return await applyTransformation(ciContext: ciContext, auxiliaryMap: auxiliaryMap) { ciImage, desc in
            var mutableDesc = desc
            let orientationValue = (mutableDesc[GainMapUtils.keyOrientation] as? UInt32) ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            
            let orientationDegrees = orientation.degrees
            if orientationDegrees % 360 == 0 {
                return nil
            }
            
            let transformed = ciImage.transformed(by: ciImage.orientationTransform(for: orientation))
            
            let shouldSwapSize = orientationDegrees % 180 != 0
            if shouldSwapSize {
                mutableDesc[GainMapUtils.keyWidth] = transformed.extent.width
                mutableDesc[GainMapUtils.keyHeight] = transformed.extent.height
                mutableDesc[GainMapUtils.keyBytesPerRow] = transformed.extent.width
            }
            
            mutableDesc[GainMapUtils.keyOrientation] = CGImagePropertyOrientation.up.rawValue
            
            return GainmainAuxiliaryTransformationResult(ciImage: transformed, desc: mutableDesc)
        }
    }
    
    /// Get the CIImage of the auxiliary gain map data, perform the custom transformation and return the result.
    ///
    /// - parameter ciContext: The ``CIContext`` to perform render. It will be better to cache the same ciContext object for later use.
    /// - parameter auxiliaryMap: The gain map root data, retrieved by ``EDRUtils.extractHDRGainMapDictionary``.
    /// - parameter action: The transformation action to perform. If you update the dimensions or orientation of the CIImage, remember to update the description.
    public func applyTransformation(
        ciContext: CIContext,
        auxiliaryMap: Dictionary<CFString, Any>,
        action: (CIImage, Dictionary<String, Any>) -> GainmainAuxiliaryTransformationResult?
    ) async -> GainMapAuxiliaryData? {
        guard var mutableDesc = auxiliaryMap[kCGImageAuxiliaryDataInfoDataDescription] as? Dictionary<String, Any> else {
            return nil
        }
        
        guard let originalWidth = mutableDesc[GainMapUtils.keyWidth] as? Int,
              let originalHeight = mutableDesc[GainMapUtils.keyHeight] as? Int,
              let bytesPerRow = mutableDesc[GainMapUtils.keyBytesPerRow] as? Int else {
            return nil
        }
        
        guard let originalBitmapData = auxiliaryMap[kCGImageAuxiliaryDataInfoData] as? Data else {
            return nil
        }
        
        var ciImage = CIImage.createFrom(
            bitmapData: originalBitmapData,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: originalWidth, height: originalHeight)
        )
        
        guard let result = action(ciImage, mutableDesc) else {
            return nil
        }
        
        ciImage = result.ciImage
        mutableDesc = result.desc
        
        guard let gainMapImageData = ciImage.getBitmapData(ciContext: ciContext) else {
            return nil
        }
        
        return GainMapAuxiliaryData(gainMapImageData: gainMapImageData, desc: mutableDesc)
    }
}

private extension CIImage {
    static func createFrom(bitmapData: Data, bytesPerRow: Int, size: CGSize) -> CIImage {
        return CIImage(
            bitmapData: bitmapData,
            bytesPerRow: bytesPerRow,
            size: size,
            format: .L8,
            colorSpace: nil
        )
    }
    
    func getBitmapData(ciContext: CIContext) -> Data? {
        let width = self.extent.width
        let height = self.extent.height
        
        let rowBytes = 1 * Int(width)
        let dataSize = rowBytes * Int(height)
        var gainMapImageData = Data(count: Int(dataSize))
        
        gainMapImageData.withUnsafeMutableBytes {
            if let baseAddress = $0.baseAddress {
                ciContext.render(
                    self,
                    toBitmap: baseAddress,
                    rowBytes: rowBytes,
                    bounds: self.extent,
                    format: .L8,
                    colorSpace: nil
                )
            }
        }
        
        return gainMapImageData
    }
}

public extension CGImagePropertyOrientation {
    var degrees: Int {
        switch self {
        case .up, .upMirrored:
            return 0
        case .down, .downMirrored:
            return 180
        case .left, .leftMirrored:
            return 180 / 2
        case .right, .rightMirrored:
            return -180 / 2
        }
    }
    
    var radians: CGFloat {
        let degrees = self.degrees
        return CGFloat(degrees) / 180 * .pi
    }
}
