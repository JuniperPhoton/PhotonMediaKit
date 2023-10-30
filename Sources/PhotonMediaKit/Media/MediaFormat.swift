//
//  File.swift
//  
//
//  Created by Photon Juniper on 2023/10/30.
//
import Foundation
import UniformTypeIdentifiers

/// Destination format to convert.
public enum ImageFormat: String, Hashable, CaseIterable, Equatable {
    case jpeg = "JPEG"
    case heif = "HEIF"
    case heif10Bit = "10 Bit HEIF"
    
    public static var allCases: [ImageFormat] = [.jpeg, .heif]
    
    public func getExtension() -> String {
        switch self {
        case .heif: return "heic"
        case .jpeg: return "jpeg"
        case .heif10Bit: return "heic"
        }
    }
    
    public func getUTType() -> UTType {
        switch self {
        case .heif: return UTType.heic
        case .jpeg: return UTType.jpeg
        case .heif10Bit: return UTType.heic
        }
    }
}

public enum VideoEncodeFormat: String, Hashable, CaseIterable, Equatable {
    case h264 = "H.264"
    case h265 = "H.265"
}

public enum VideoContainerFormat: String, Hashable, CaseIterable, Equatable {
    case mp4 = "MP4"
    case mov = "MOV"
}
