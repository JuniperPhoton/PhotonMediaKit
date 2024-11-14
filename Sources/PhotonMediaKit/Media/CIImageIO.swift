//
//  ImageSaver.swift
//  MyerTidy
//
//  Created by Photon Juniper on 2023/1/4.
//

import Foundation
import Photos

public actor CIImageIO {
    enum IOError: Error {
        case notAuthorized
        case render
        case other
    }
    
    /// Load CIImage from a URL.
    ///
    /// - parameter url: The file URL.
    /// - parameter decodeToHDR: Whether decode to HDR or not. This will take effect on iOS 17 or macOS 14 or above.
    public static func loadCIImage(url: URL, decodeToHDR: Bool) async -> CIImage? {
        var options: [CIImageOption: Any] = [:]
        if #available(iOS 17.0, macOS 14.0, *), decodeToHDR {
            options[.expandToHDR] = true
        }
        let ciImage = CIImage(contentsOf: url, options: options)
        LibLogger.imageIO.log("loadCIImage, extent: \(String(describing: ciImage?.extent))")
        return ciImage
    }
    
    /// Load CIImage from a file data.
    ///
    /// - parameter data: The file data.
    /// - parameter utType: The accurate UTType of the data. Can be constructed from a file name.
    /// - parameter decodeToHDR: Whether decode to HDR or not. This will take effect on iOS 17 or macOS 14 or above.
    ///
    /// Note: Decoding
    public static func loadCIImage(data: Data, utType: UTType?, decodeToHDR: Bool) async -> CIImage? {
        var dic: [CFString: Any] = [:]
        
        if let utType {
            dic[kCGImageSourceTypeIdentifierHint] = utType.identifier
        }
        
        if #available(iOS 17.0, macOS 14.0, *), decodeToHDR {
            dic[kCGImageSourceDecodeRequest] = kCGImageSourceDecodeToHDR
        }
        
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            dic as CFDictionary
        ) else {
            print("source is nil")
            return nil
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, dic as CFDictionary) else {
            print("cgImage is nil")
            return nil
        }
        
        LibLogger.imageIO.log("loadCIImage, \(cgImage.width)")
        
        let orientation = await CGImageIO.shared.getExifOrientation(data: data, utType: utType)
        
        let ciImage = CIImage(
            cgImageSource: source,
            index: 0
        )
        let transform = ciImage.orientationTransform(for: orientation)
        let transformed = ciImage.transformed(by: transform)
        
        LibLogger.imageIO.log("loadCIImage, orientation: \(orientation.rawValue), utType: \(utType?.identifier ?? "nil"), extent: \(String(describing: transformed.extent))")
        
        return transformed
    }
    
    public let ciContext: CIContext
    
    public init(ciContext: CIContext = CIContext()) {
        self.ciContext = ciContext
    }
    
    public func loadCGImage(ciImage: CIImage?) async -> CGImage? {
        guard let ciImage = ciImage else {
            return nil
        }
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func saveImage(file: URL, toURL: URL, toFormat: ImageFormat) async throws -> Bool {
        guard let utType = file.getUTType() else {
            return false
        }
        
        let data = try Data(contentsOf: file)
        
        let file: URL? = try? await saveUsingCIImage(
            data: data,
            toURL: toURL,
            originalIdentifier: utType.identifier,
            toFormat: toFormat
        )
        
        return file != nil
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func saveImage(
        data: Data,
        asset: PHAsset,
        resource: PHAssetResource,
        toFormat: ImageFormat
    ) async throws -> Bool {
        guard let tempFile = MediaAssetWriter.shared.createTempFileToSave(
            originalFilename: resource.originalFilename,
            utType: toFormat.getUTType()
        ) else {
            throw IOError.other
        }
        
        let file: URL? = try? await saveUsingCIImage(
            data: data,
            toURL: tempFile,
            originalIdentifier: resource.uniformTypeIdentifier,
            toFormat: toFormat
        )
        
        guard let outputFile = file else {
            throw IOError.render
        }
        
        return await MediaAssetWriter.shared.saveMediaFileToAlbum(
            file: outputFile,
            location: asset.location,
            deleteOnComplete: true
        )
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    private func saveUsingCIImage(data: Data,
                                  toURL: URL,
                                  originalIdentifier: String,
                                  toFormat: ImageFormat) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let filter = CIRAWFilter(imageData: data, identifierHint: originalIdentifier)
            
            LibLogger.imageIO.log("convert to \(toFormat.rawValue)")
            
            guard let output = filter?.outputImage else {
                continuation.resume(throwing: IOError.render)
                return
            }
            
            let originalColorSpace = output.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            
            do {
                switch toFormat {
                case .jpeg:
                    try ciContext.writeJPEGRepresentation(
                        of: output,
                        to: toURL,
                        colorSpace: originalColorSpace
                    )
                case .heif:
                    try ciContext.writeHEIFRepresentation(
                        of: output,
                        to: toURL,
                        format: .ARGB8,
                        colorSpace: originalColorSpace
                    )
                case.heif10Bit:
                    try ciContext.writeHEIF10Representation(
                        of: output,
                        to: toURL,
                        colorSpace: originalColorSpace,
                        options: [:]
                    )
                }
                
                continuation.resume(returning: toURL)
            } catch {
                continuation.resume(throwing: IOError.render)
            }
        }
    }
}
