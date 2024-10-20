//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/1/25.
//

import Foundation
import CoreImage

public struct GainMapAuxiliaryDataResult {
    public let gainMapImageData: Data
    public let desc: Dictionary<String, Any>
    
    init(gainMapImageData: Data, desc: Dictionary<String, Any>) {
        self.gainMapImageData = gainMapImageData
        self.desc = desc
    }
}

public struct GainMapAuxiliaryImageResult {
    public let ciImage: CIImage
    public let desc: Dictionary<String, Any>
    
    public init(ciImage: CIImage, desc: Dictionary<String, Any>) {
        self.ciImage = ciImage
        self.desc = desc
    }
}

/// The dictionary representation of the gain map info and its type.
public struct GainMapInfoDictionaryWithType {
    public let dictionary: CFDictionary
    public let type: GainMapType
    
    public init(_ dictionary: CFDictionary, _ type: GainMapType) {
        self.dictionary = dictionary
        self.type = type
    }
    
    public func replacing(_ dictionary: CFDictionary) -> GainMapInfoDictionaryWithType {
        return GainMapInfoDictionaryWithType(dictionary, self.type)
    }
    
    public func replacing(_ dictionary: Dictionary<CFString, Any>) -> GainMapInfoDictionaryWithType {
        return GainMapInfoDictionaryWithType(dictionary as CFDictionary, self.type)
    }
}

public enum GainMapType {
    /// The new standardized ISO gain map that supposed to be supported by various platforms.
    case isoGainMap
    
    /// Thed old Apple Gain Map originating from iPhone 12.
    case hdrGainMap
    
    public var auxiliarayType: AuxiliaryDataType {
        switch self {
        case .isoGainMap:
            return .isoGainMap
        case .hdrGainMap:
            return .hdrGainMap
        }
    }
    
    /// Get the newest Gain Map type supported by the current platform.
    /// If you want to generate the gain map image and write it to the output file, please make sure to get the gain map type by this method.
    public static func getNewestSupportedType() -> GainMapType {
        if #available(iOS 18.0, *) {
            return .isoGainMap
        } else {
            return .hdrGainMap
        }
    }
}

public struct GainMapBitmapInfo {
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
    
    /// The type of the gain map.
    public let type: GainMapType
    
    /// Convenient way to create the ``CIImage`` of this gain map.
    public func toCIImage(applyOrientation: Bool = false) -> CIImage? {
        let image = CIImage(
            bitmapData: data,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: height),
            format: .L8,
            colorSpace: nil
        )
        
        if applyOrientation {
            return image.oriented(orientation)
        } else {
            return image
        }
    }
}

public class GainMapUtils {
    public static let keyWidth = "Width"
    public static let keyHeight = "Height"
    public static let keyBytesPerRow = "BytesPerRow"
    public static let keyOrientation = "Orientation"
    
    private static var keyHDRGainMapHeadroom = "HDRGainMapHeadroom"
    private static var keyAlternateHeadroom = "AlternateHeadroom"
    private static var keyHDRGainMapVersion = "HDRGainMapVersion"
    private static var keyVersion = "Version"
    
    public static let shared = GainMapUtils()
    
    public func updateData(
        auxiliaryMap: Dictionary<CFString, Any>,
        transformed: GainMapAuxiliaryDataResult
    ) async -> Dictionary<CFString, Any> {
        var mutable = auxiliaryMap
        mutable[kCGImageAuxiliaryDataInfoData] = transformed.gainMapImageData
        mutable[kCGImageAuxiliaryDataInfoDataDescription] = transformed.desc
        return mutable
    }
    
    /// Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public func extractHDRGainMap(url: URL, type: GainMapType) async -> GainMapBitmapInfo? {
        let _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        return await extractGainMap(data: data, type: type)
    }
    
    /// Extract the HDR gain map original data and parse as ``CFDictionary``.
    public func extractGainMapDictionary(data: Data, type: GainMapType) async -> GainMapInfoDictionaryWithType? {
        if let result = await CGImageIO.shared.extractAuxiliaryDictionary(data: data, type: type.auxiliarayType) {
            return GainMapInfoDictionaryWithType(result, type)
        }
        
        return nil
    }
    
    /// Extract the HDR gain map original data and parse as ``CFDictionary``.
    public func extractGainMapDictionaryWithFallback(data: Data) async -> GainMapInfoDictionaryWithType? {
        if let result = await CGImageIO.shared.extractAuxiliaryDictionary(data: data, type: .isoGainMap) {
            return GainMapInfoDictionaryWithType(result, .isoGainMap)
        }
        
        if let result = await CGImageIO.shared.extractAuxiliaryDictionary(data: data, type: .hdrGainMap) {
            return GainMapInfoDictionaryWithType(result, .hdrGainMap)
        }
        
        return nil
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
    
    // Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public func extractGainMap(data: Data, type: GainMapType) async -> GainMapBitmapInfo? {
        guard let result = await extractGainMapDictionary(data: data, type: type) else {
            return nil
        }
        guard let dic = result.dictionary as? Dictionary<CFString, Any> else {
            return nil
        }
        return await extractGainMap(auxiliaryMap: dic, type: result.type)
    }
    
    public func extractGainMapWithFallback(data: Data) async -> GainMapBitmapInfo? {
        if let result = await extractGainMap(data: data, type: .isoGainMap) {
            return result
        }
        
        return await extractGainMap(data: data, type: .hdrGainMap)
    }
    
    /// Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public func extractGainMap(auxiliaryMap: Dictionary<CFString, Any>, type: GainMapType) async -> GainMapBitmapInfo? {
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
                    
                    debugPrint("extractHDRGainMap, tag name: \(String(describing: name)), value: \(String(describing: value))")
                    
                    if let value = value as? String, let float = Float(value) {
                        if name == GainMapUtils.keyHDRGainMapHeadroom || name == GainMapUtils.keyAlternateHeadroom {
                            gainMapHeadroom = CGFloat(float)
                        }
                    }
                    
                    if name == GainMapUtils.keyHDRGainMapVersion || name == GainMapUtils.keyVersion {
                        valid = true
                    }
                }
            }
            
            if !valid {
                return nil
            }
            
            debugPrint("extractHDRGainMap desc is \(desc)")
            debugPrint("extractHDRGainMap metadata is \(metadata)")
            
            return GainMapBitmapInfo(
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                pixelFormat: pixelFormat,
                orientation: cgOrientation,
                headroom: gainMapHeadroom,
                data: data,
                type: type
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
        rect: CGRect,
        rotateOrientationToUp: Bool,
        flipHorizontally: Bool
    ) async -> GainMapAuxiliaryDataResult? {
        return await applyTransformation(ciContext: ciContext, auxiliaryMap: auxiliaryMap) { ciImage, desc in
            return processCrop(
                ciImage: ciImage,
                metadata: desc,
                rect: rect,
                rotateOrientationToUp: rotateOrientationToUp,
                flipHorizontally: flipHorizontally
            )
        }
    }
    
    /// Helper method to crop the gain map image and update the metadata.
    public func processCrop(
        ciImage: CIImage,
        metadata: Dictionary<String, Any>,
        rect: CGRect,
        rotateOrientationToUp: Bool,
        flipHorizontally: Bool
    ) -> GainMapAuxiliaryImageResult {
        var mutableDesc = metadata
        
        var cropped = ciImage.cropped(to: rect)
        
        cropped = cropped.transformed(
            by: CGAffineTransform.init(
                translationX: -cropped.extent.minX,
                y: -cropped.extent.minY
            )
        )
        
        if rotateOrientationToUp {
            let orientationValue = (mutableDesc[GainMapUtils.keyOrientation] as? UInt32) ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            
            cropped = cropped.transformed(by: cropped.orientationTransform(for: orientation))
        }
        
        if flipHorizontally {
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        
        mutableDesc[GainMapUtils.keyWidth] = cropped.extent.width
        mutableDesc[GainMapUtils.keyHeight] = cropped.extent.height
        mutableDesc[GainMapUtils.keyBytesPerRow] = cropped.extent.width
        
        return GainMapAuxiliaryImageResult(ciImage: cropped, desc: mutableDesc)
    }
    
    /// Scale the ``gainMap`` image to match the ``primaryImage``.
    ///
    /// On iOS 18, if the dimensions of gainMap image is not the half of the primary image,
    /// when zooming photos there will be over-saturated effect on the image.
    public func scaleGainMap(toMatch primaryImage: CIImage, gainMap: CIImage) -> CIImage {
        let primaryExtent = primaryImage.extent
        let targetWidth = primaryExtent.width / 2
        let targetHeight = primaryExtent.height / 2
        let targetScaleX = targetWidth / gainMap.extent.width
        let targetScaleY = targetHeight / gainMap.extent.height
                
        let output = gainMap.transformed(by: CGAffineTransform(scaleX: targetScaleX, y: targetScaleY))
        let croppedRect = CGRect(
            x: 0,
            y: 0,
            width: round(targetWidth),
            height: round(targetHeight)
        )
        
        return output.cropped(to: croppedRect)
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
    ) async -> GainMapAuxiliaryDataResult? {
        return await applyTransformation(ciContext: ciContext, auxiliaryMap: auxiliaryMap) { ciImage, desc in
            var mutableDesc = desc
            let orientationValue = (mutableDesc[GainMapUtils.keyOrientation] as? UInt32) ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            
            let orientationDegrees = orientation.degrees
            if orientationDegrees % 360 == 0 {
                return nil
            }
            
            let transformed = ciImage.transformed(by: ciImage.orientationTransform(for: orientation))
            
            mutableDesc[GainMapUtils.keyWidth] = transformed.extent.width
            mutableDesc[GainMapUtils.keyHeight] = transformed.extent.height
            mutableDesc[GainMapUtils.keyBytesPerRow] = transformed.extent.width
            mutableDesc[GainMapUtils.keyOrientation] = CGImagePropertyOrientation.up.rawValue
            
            return GainMapAuxiliaryImageResult(ciImage: transformed, desc: mutableDesc)
        }
    }
    
    /// Get the CIImage of the auxiliary gain map data if exists.
    public func getGainMapImage(auxiliaryMap: Dictionary<CFString, Any>) async -> CIImage? {
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
        
        return CIImage.createFrom(
            bitmapData: originalBitmapData,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: originalWidth, height: originalHeight)
        )
    }
    
    /// Get the CIImage of the auxiliary gain map data, perform the custom transformation and return the result.
    ///
    /// - parameter ciContext: The ``CIContext`` to perform render. It will be better to cache the same ciContext object for later use.
    /// - parameter auxiliaryMap: The gain map root data, retrieved by ``EDRUtils.extractHDRGainMapDictionary``.
    /// - parameter action: The transformation action to perform. If you update the dimensions or orientation of the CIImage, remember to update the description.
    public func applyTransformation(
        ciContext: CIContext,
        auxiliaryMap: Dictionary<CFString, Any>,
        action: (CIImage, Dictionary<String, Any>) async -> GainMapAuxiliaryImageResult?
    ) async -> GainMapAuxiliaryDataResult? {
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
        
        guard let result = await action(ciImage, mutableDesc) else {
            return nil
        }
        
        ciImage = result.ciImage
        mutableDesc = result.desc
        
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        let targetBytesPerRow = nextMultipleOfFour(after: width)
        
        guard let gainMapImageData = ciImage.getBitmapData(ciContext: ciContext, bytesPerRow: targetBytesPerRow) else {
            return nil
        }
        
        mutableDesc[GainMapUtils.keyBytesPerRow] = targetBytesPerRow
        mutableDesc[GainMapUtils.keyWidth] = width
        mutableDesc[GainMapUtils.keyHeight] = height
        
        print("gain map apply transformation, targetBytesPerRow \(targetBytesPerRow), width \(width), height \(height)")
        
        return GainMapAuxiliaryDataResult(gainMapImageData: gainMapImageData, desc: mutableDesc)
    }
    
    private func nextMultipleOfFour(after x: Int) -> Int {
        // Find the remainder when x is divided by 4
        let remainder = x % 4
        
        // If the remainder is 0, x is already divisible by 4, so add 4
        if remainder == 0 {
            return x
        } else {
            // Otherwise, add the difference between 4 and the remainder to x
            return x + (4 - remainder)
        }
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
    
    func getBitmapData(ciContext: CIContext, bytesPerRow: Int) -> Data? {
        let height = self.extent.height
        
        let dataSize = bytesPerRow * Int(height)
        var gainMapImageData = Data(count: Int(dataSize))
        
        gainMapImageData.withUnsafeMutableBytes {
            if let baseAddress = $0.baseAddress {
                ciContext.render(
                    self,
                    toBitmap: baseAddress,
                    rowBytes: bytesPerRow,
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
