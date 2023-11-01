//
//  ImageSaver.swift
//  MyerTidy
//
//  Created by Photon Juniper on 2023/1/4.
//

import Foundation
import Photos

public actor CIImageIO {
    private let sharedCIContext: CIContext = {
        return CIContext()
    }()
    
    enum IOError: Error {
        case notAuthorized
        case render
        case other
    }
    
    public init() {
        // empty
    }
    
    public func loadCGImage(ciImage: CIImage?) async -> CGImage? {
        guard let ciImage = ciImage else {
            return nil
        }
        return sharedCIContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func saveImage(file: URL, toURL: URL, toFormat: ImageFormat) async throws -> Bool {
        guard let utType = file.getUTType() else {
            return false
        }
        
        let data = try Data(contentsOf: file)
        
        let file: URL? = try? await saveUsingCIImage(data: data,
                                                     toURL: toURL,
                                                     originalIdentifier: utType.identifier,
                                                     toFormat: toFormat)
        
        return file != nil
    }
    
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
    public func saveHDRImage(data: Data,
                             asset: PHAsset,
                             resource: PHAssetResource) async throws -> Bool {
        guard let tempFile = MediaAssetWriter.shared.createTempFileToSave(
            originalFilename: resource.originalFilename,
            utType: .heic
        ) else {
            throw IOError.other
        }
        
        let file: URL? = try? await saveUsingCIImageWithHDR(
            data: data,
            toURL: tempFile,
            originalIdentifier: resource.uniformTypeIdentifier
        )
        
        guard let outputFile = file else {
            throw IOError.render
        }
        
        return await MediaAssetWriter.shared.saveMediaFileToAlbum(
            file: outputFile,
            deleteOnComplete: true
        )
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    public func saveImage(data: Data,
                          asset: PHAsset,
                          resource: PHAssetResource,
                          toFormat: ImageFormat) async throws -> Bool {
        guard let tempFile = MediaAssetWriter.shared.createTempFileToSave(
            originalFilename: resource.originalFilename,
            utType: toFormat.getUTType()
        ) else {
            throw IOError.other
        }
        
        let file: URL? = try? await saveUsingCIImage(data: data,
                                                     toURL: tempFile,
                                                     originalIdentifier: resource.uniformTypeIdentifier,
                                                     toFormat: toFormat)
        
        guard let outputFile = file else {
            throw IOError.render
        }
        
        return await MediaAssetWriter.shared.saveMediaFileToAlbum(file: outputFile, deleteOnComplete: true)
    }
    
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
    private func saveUsingCIImageWithHDR(data: Data,
                                         toURL: URL,
                                         originalIdentifier: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let originalColorSpace: CGColorSpace?
            
            if let ciImage = CIImage(data: data, options: [.expandToHDR: true]) {
                originalColorSpace = ciImage.colorSpace
            } else {
                originalColorSpace = CIImage(data: data)?.colorSpace
            }
            
            let filter = CIRAWFilter(imageData: data, identifierHint: originalIdentifier)
            if let colorspace = originalColorSpace, CGColorSpaceUsesITUR_2100TF(colorspace) {
                filter?.extendedDynamicRangeAmount = 1.0
            }
            
            guard let output = filter?.outputImage else {
                continuation.resume(throwing: IOError.render)
                return
            }
            
            do {
                let colorSpace: CGColorSpace
                if let imageColorSpace = originalColorSpace, CGColorSpaceUsesITUR_2100TF(imageColorSpace) {
                    colorSpace = imageColorSpace
                    LibLogger.imageIO.log("convert to HDR CGColorSpaceUsesITUR_2100TF true")
                } else  {
                    colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
                    LibLogger.imageIO.log("convert to HDR CGColorSpaceUsesITUR_2100TF false for \(String(describing: originalColorSpace))")
                }
                
                LibLogger.imageIO.log("convert to HDR using \(String(describing: colorSpace))")
                
                try sharedCIContext.writeHEIF10Representation(of: output,
                                                              to: toURL,
                                                              colorSpace: colorSpace,
                                                              options: [:])
                
                continuation.resume(returning: toURL)
            } catch {
                LibLogger.imageIO.log("error convert to HDR \(error.localizedDescription)")
                continuation.resume(throwing: IOError.render)
            }
        }
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
            
            do {
                switch toFormat {
                case .jpeg:
                    try sharedCIContext.writeJPEGRepresentation(
                        of: output,
                        to: toURL,
                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
                    )
                case .heif:
                    try sharedCIContext.writeHEIFRepresentation(
                        of: output,
                        to: toURL,
                        format: .ARGB8,
                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
                    )
                case.heif10Bit:
                    try sharedCIContext.writeHEIF10Representation(
                        of: output,
                        to: toURL,
                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
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
