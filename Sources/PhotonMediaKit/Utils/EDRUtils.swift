//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/10/30.
//

import Foundation
import CoreImage
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct HDRGainMapInfo {
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
        var gainImage = CIImage(
            bitmapData: data,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: height),
            format: .L8,
            colorSpace: nil
        )
        
        let transform = gainImage.orientationTransform(for: orientation)
        gainImage = gainImage.transformed(by: transform)
        gainImage = gainImage.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
        
        return gainImage
    }
}

/// Provides information about EDR support on this device.
public class EDRUtils {
    private static var keyHDRGainMapHeadroom = "HDRGainMapHeadroom"
    private static var keyHDRGainMapVersion = "HDRGainMapVersion"
    
    public static var supportEDRByOS: Bool {
        if #available(iOS 16.0, macOS 13.0, *) {
            true
        } else {
            false
        }
    }
    
    public static var potentialEDRHeadroom: CGFloat {
        if #available(iOS 17.0, macOS 14.0, tvOS 16.0, *) {
#if canImport(UIKit)
            UIScreen.main.potentialEDRHeadroom
#elseif canImport(AppKit)
            (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0)
#endif
        } else {
            1.0
        }
    }
    
    public static var supportEDRByDevice: Bool {
        if #available(iOS 17.0, macOS 14.0, tvOS 16.0, *) {
#if canImport(UIKit)
            UIScreen.main.potentialEDRHeadroom > 1.0
#elseif canImport(AppKit)
            (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0) > 1.0
#endif
        } else {
            false
        }
    }
    
    /// Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public static func extractHDRGainMap(url: URL) async -> HDRGainMapInfo? {
        let _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        return await extractHDRGainMap(data: data)
    }
    
    /// Extract the HDR gain map original data and parse as ``CFDictionary``.
    public static func extractHDRGainMapDictionary(data: Data) async -> CFDictionary? {
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
    
    /// Extract the HDR gain map information from the data and return ``HDRGainMapInfo``.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public static func extractHDRGainMap(data: Data) async -> HDRGainMapInfo? {
        guard let auxiliaryData = await extractHDRGainMapDictionary(data: data) as? Dictionary<CFString, Any> else {
            return nil
        }
        
        if let desc = auxiliaryData[kCGImageAuxiliaryDataInfoDataDescription] as? Dictionary<String, Any>,
           let metadata = auxiliaryData[kCGImageAuxiliaryDataInfoMetadata],
           let data = auxiliaryData[kCGImageAuxiliaryDataInfoData] as? Data {
            
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
                    if name == EDRUtils.keyHDRGainMapHeadroom, let value = value as? String, let float = Float(value) {
                        gainMapHeadroom = CGFloat(float)
                    }
                    
                    if name == EDRUtils.keyHDRGainMapVersion {
                        valid = true
                    }
                }
            }
            
            if !valid {
                return nil
            }
            
            debugPrint("extractHDRGainMap desc is \(desc)")
            debugPrint("extractHDRGainMap metadata is \(metadata)")
            
            return HDRGainMapInfo(
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
    
    /// Extract headroom from the EXIF metadata.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public static func extractHeadroom(url: URL) async -> CGFloat? {
        let _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        return await extractHeadroom(data: data)
    }
    
    /// Extract headroom from the EXIF metadata.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public static func extractHeadroom(data: Data) async -> CGFloat? {
        guard let map = await CGImageIO.shared.getExifMap(data: data) else {
            return nil
        }
        
        guard let maker = map["{MakerApple}"] as? Dictionary<String, Any> else {
            return nil
        }
        
        guard let maker33 = maker["33"] as? Float else {
            return nil
        }
        
        guard let maker48 = maker["48"] as? Float else {
            return nil
        }
        
        // Extract the metadata keys from the image.
        let stops: Float
        
        // Convert the metadata to the number of stops
        // (factors of 2) that the gain map should apply
        // to the image.
        if maker33 < 1.0 {
            if maker48 <= 0.01 {
                stops = -20.0 * maker48 + 1.8
            } else {
                stops = -0.101 * maker48 + 1.601
            }
        } else {
            if maker48 <= 0.01 {
                stops = -70.0*maker48 + 3.0
            } else {
                stops = -0.303*maker48 + 2.303
            }
        }
        
        // Convert the stops to linear headroom.
        let headroom = pow(2.0, max(stops, 0.0))
        return CGFloat(headroom)
    }
}
