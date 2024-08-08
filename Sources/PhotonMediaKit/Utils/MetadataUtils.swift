//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/8/8.
//

import Foundation
import CoreImage
import ImageIO

public typealias CIImageProperties = Dictionary<String, Any>

public class MetadataUtils {
    public static let shared = MetadataUtils()
    
    private init() {
        // empty
    }
    
    /// Remove the portrait info in the properties' Apple Maker dictionary.
    ///
    /// After doing so, the photos with this metadata won't be recognized as Portrait Photo in the Photos app.
    public func removePortraitInfoInAppleMaker(_ properties: inout CIImageProperties) {
        if var appleMaker = properties[kCGImagePropertyMakerAppleDictionary as String] as? Dictionary<String, Any> {
            // https://exiftool.org/TagNames/Apple.html SceneFlags
            appleMaker.removeValue(forKey: "25")
            properties[kCGImagePropertyMakerAppleDictionary as String] = appleMaker
        }
    }
    
    /// Remove the HDR info in the properties' Apple Maker dictionary.
    ///
    /// After doing so, the photos with this metadata won't have HDR effect in the Photos app, regardless of the gain map image.
    public func removeHDRInfoInAppleMaker(_ properties: inout CIImageProperties) {
        if var appleMaker = properties[kCGImagePropertyMakerAppleDictionary as String] as? Dictionary<String, Any> {
            // The values are mentioned in this documentation:
            // https://developer.apple.com/documentation/appkit/images_and_pdf/applying_apple_hdr_effect_to_your_photos
            appleMaker.removeValue(forKey: "48")
            appleMaker.removeValue(forKey: "33")
            properties[kCGImagePropertyMakerAppleDictionary as String] = appleMaker
        }
    }
}
