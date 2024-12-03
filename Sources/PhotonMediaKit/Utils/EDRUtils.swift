//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/10/30.
//

import Foundation
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Provides information about EDR support on this device.
public class EDRUtils {
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
    
    /// Extract headroom from the EXIF metadata.
    ///
    /// > Note: This only supports images captured by iPhone, which will have Apple metadata.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public static func extractHeadroomFromAppleMetadata(url: URL) async -> CGFloat? {
        let _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            return nil
        }
        
        return await extractHeadroomFromAppleMetadata(data: data, utType: utType)
    }
    
    /// Extract headroom from the EXIF metadata.
    ///
    /// > Note: This only supports images captured by iPhone, which will have Apple metadata.
    ///
    /// See more: https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
    public static func extractHeadroomFromAppleMetadata(data: Data, utType: UTType?) async -> CGFloat? {
        guard let map = await CGImageIO.shared.getProperties(data: data, utType: utType) else {
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
