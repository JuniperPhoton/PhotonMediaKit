//
//  File.swift
//  
//
//  Created by Photon Juniper on 2024/3/13.
//

import Foundation

class PhotonMediaKitBundleLocator {}

extension Bundle {
    public static var mediaKitBundle: Bundle {
#if SWIFT_PACKAGE
        return Bundle.module
#else
        return Bundle(for: PhotonMediaKitBundleLocator.self)
#endif
    }
}
