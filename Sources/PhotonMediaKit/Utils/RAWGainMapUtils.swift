//
//  RAWGainMapUtils.swift
//  PhotonMediaKit
//
//  Created by JuniperPhoton on 2024/11/14.
//
import Foundation
import CoreImage
import UniformTypeIdentifiers

/// Utility class to generate HDR Gain Map image from RAW image.
public final class RAWGainMapUtils {
    public enum EDRAmount {
        case normal
        case high
        
        var floatValue: Float {
            switch self {
            case .normal:
                return 1.0
            case .high:
                return 2.0
            }
        }
    }
    
    public static let shared = RAWGainMapUtils()
    
    /// Generate Gain Map Image attached file from the RAW image data.
    ///
    /// The output image will be a SDR photo in DisplayP3 color space, attached with HDR Gain Map.
    ///
    /// - parameter rawImageData: RAW image data.
    /// - parameter utType: The accurate UTType of this image data.
    /// - parameter outputFile: The file to write into.
    /// - parameter ciContext: The CIContext to use. Must be in ITU-R BT.2100 PQ color space.
    /// - parameter edrAmount: The amount of extended dynamic range to apply.
    @available(iOS 18.0, macOS 15.0, *)
    public func generateSDRWithGainMap(
        rawImageData data: Data,
        utType: UTType,
        outputFile: URL,
        ciContext: CIContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ)!]),
        edrAmount: EDRAmount = .normal
    ) async -> URL? {
        guard let rawFilter = CIRAWFilter(imageData: data, identifierHint: utType.identifier) else {
            return nil
        }
        
        rawFilter.extendedDynamicRangeAmount = edrAmount.floatValue
        
        guard let rawOutput = rawFilter.outputImage else {
            return nil
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        
        do {
            try ciContext.writeHEIFRepresentation(
                of: rawOutput,
                to: outputFile,
                format: .ARGB8,
                colorSpace: colorSpace,
                options: [.hdrImage: rawOutput]
            )
            
            return outputFile
        } catch {
            LibLogger.imageIO.error("Error on writing gain map image: \(error)")
            return nil
        }
    }
    
    /// Generate Gain Map Image attached file from the RAW image URL.
    ///
    /// The output image will be a SDR photo in DisplayP3 color space, attached with HDR Gain Map.
    ///
    /// - parameter outputFile: RAW image url.
    /// - parameter outputFile: The file to write into.
    /// - parameter ciContext: The CIContext to use. Must be in ITU-R BT.2100 PQ color space.
    /// - parameter edrAmount: The amount of extended dynamic range to apply.
    @available(iOS 18.0, macOS 15.0, *)
    public func generateSDRWithGainMap(
        rawImageURL url: URL,
        outputFile: URL,
        ciContext: CIContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ)!]),
        edrAmount: EDRAmount = .normal
    ) async -> URL? {
        guard let rawFilter = CIRAWFilter(imageURL: url) else {
            return nil
        }
        
        rawFilter.extendedDynamicRangeAmount = edrAmount.floatValue
        
        guard let rawOutput = rawFilter.outputImage else {
            return nil
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        
        do {
            try ciContext.writeHEIFRepresentation(
                of: rawOutput,
                to: outputFile,
                format: .ARGB8,
                colorSpace: colorSpace,
                options: [.hdrImage: rawOutput]
            )
            
            return outputFile
        } catch {
            LibLogger.imageIO.error("Error on writing gain map image: \(error)")
            return nil
        }
    }
}
