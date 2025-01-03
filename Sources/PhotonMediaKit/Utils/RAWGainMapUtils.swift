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
    /// Just like ``generateSDRWithGainMap(rawImageURL:outputFile:ciContext:edrAmount:scaleFactor:)``,
    /// this method accepts raw image `Data` and the its `UTType` instead of URL.
    @available(iOS 18.0, macOS 15.0, *)
    public func generateSDRWithGainMap(
        rawImageData data: Data,
        utType: UTType,
        outputFile: URL,
        edrAmount: EDRAmount = .normal,
        scaleFactor: Float = 0.5
    ) async -> URL? {
        guard let rawFilter = CIRAWFilter(imageData: data, identifierHint: utType.identifier) else {
            return nil
        }
        
        rawFilter.extendedDynamicRangeAmount = edrAmount.floatValue
        rawFilter.scaleFactor = scaleFactor
        
        guard let hdrOutput = rawFilter.outputImage else {
            return nil
        }
        
        rawFilter.extendedDynamicRangeAmount = 0.0
        
        guard let sdrOutput = rawFilter.outputImage else {
            return nil
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        
        do {
            // Must use CIContext with no specific working color space.
            try CIContext().writeHEIFRepresentation(
                of: sdrOutput,
                to: outputFile,
                format: .ARGB8,
                colorSpace: colorSpace,
                options: [.hdrImage: hdrOutput]
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
    /// - parameter rawImageURL: RAW image url.
    /// - parameter outputFile: The file to write into. Must be a HEIF file.
    /// - parameter ciContext: The `CIContext` to use. Must be in ITU-R BT.2100 PQ color space.
    /// - parameter edrAmount: The amount of extended dynamic range to apply.
    /// - parameter scaleFactor: The scale factor to apply to the image. Default is 0.5.
    /// - returns: The output file you provided if success. Nil if fail.
    @available(iOS 18.0, macOS 15.0, *)
    public func generateSDRWithGainMap(
        rawImageURL url: URL,
        outputFile: URL,
        edrAmount: EDRAmount = .normal,
        scaleFactor: Float = 0.5
    ) async -> URL? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            return nil
        }
        
        return await generateSDRWithGainMap(
            rawImageData: data,
            utType: utType,
            outputFile: outputFile,
            edrAmount: edrAmount,
            scaleFactor: scaleFactor
        )
    }
}
