//
//  File.swift
//  
//
//  Created by Photon Juniper on 2023/10/30.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Provides information about EDR support on this device.
public class EDRUtils {
    public static var supportEDRByOS: Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            true
        } else {
            false
        }
    }
    
    public static var supportEDRByDevice: Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
#if canImport(UIKit)
            UIScreen.main.potentialEDRHeadroom > 1.0
#elseif canImport(AppKit)
            (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0) > 1.0
#endif
        } else {
            false
        }
    }
}
