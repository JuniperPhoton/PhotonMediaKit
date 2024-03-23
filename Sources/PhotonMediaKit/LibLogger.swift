//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/10/30.
//

import Foundation
import OSLog

class LibLogger {
    static let mediaLoader = Logger(subsystem: "com.juniperphoton.photonmediakit", category: "mediaLoader")
    static var libDefault = Logger(subsystem: "com.juniperphoton.photonmediakit", category: "libDefault")
    static var imageIO = Logger(subsystem: "com.juniperphoton.photonmediakit", category: "imageIO")
    static var depthMap = Logger(subsystem: "com.juniperphoton.photonmediakit", category: "depthMap")
}
