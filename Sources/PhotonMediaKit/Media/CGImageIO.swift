//
//  ImageIO.swift
//  MyerSplash2
//
//  Created by Photon Juniper on 2023/2/24.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Provides common methods to use about processing image data.
/// You use the ``shared`` to  get the shared instance.
/// The instance is an Swift actor, so all the method is isolated inside this actor, therefore, you must await the methods to complete.
public actor CGImageIO {
    public struct IOError: Error {
        let message: String
        
        init(_ message: String = "") {
            self.message = message
        }
    }
    
    public static let shared = CGImageIO()
    
    private init() {
        // empty
    }
    
    /// Load the data as ``CGImage``.
    /// - parameter data: data to be loaded as ``CGImage``
    public func loadCGImage(data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw IOError("Failed to CGImageSourceCreateWithData")
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw IOError("Failed to CGImageSourceCreateImageAtIndex")
        }
        
        return cgImage
    }
    
    /// Scale image to the specified factor.
    /// Note that if rotationDegrees % 180 is not zero, the width and height parameters must be the original ones before rotation.
    public func scaleCGImage(
        image: CGImage,
        scaleFactor: CGFloat,
        rotationDegrees: Int = 0
    ) -> CGImage? {
        var finalW = CGFloat(image.width) * scaleFactor
        var finalH = CGFloat(image.height) * scaleFactor
        if rotationDegrees % 180 != 0 {
            let temp = finalW
            finalW = finalH
            finalH = temp
        }
        return scaleCGImage(image: image, width: finalW, height: finalH, rotationDegrees: rotationDegrees)
    }
    
    /// Scale image to the specified width and height.
    /// - parameter width: The final width after rotation
    /// - parameter height: The final width after rotation
    /// - parameter rotationDegrees: The rotation in degrees
    public func scaleCGImage(
        image: CGImage,
        width: CGFloat,
        height: CGFloat,
        rotationDegrees: Int = 0
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        let radians = Double(rotationDegrees) * Double.pi / 180.0
        let shouldSwapSize = rotationDegrees % 180 != 0
        
        context.translateBy(x: width / 2, y: height / 2)
        context.rotate(by: radians)
        
        if shouldSwapSize {
            context.translateBy(x: -height / 2, y: -width / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: height, height: width))
        } else {
            context.translateBy(x: -width / 2, y: -height / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return context.makeImage()
    }
    
    /// Save the image date to a file.
    /// - parameter file: file URL  to be saved into
    /// - parameter data: the data to be saved
    /// - parameter utType: a ``UTType`` to identify the image format
    public func saveToFile(file: URL, data: Data, utType: UTType) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw IOError()
        }
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw IOError()
        }
        
        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        guard let dest = CGImageDestinationCreateWithURL(file as CFURL,
                                                         utType.identifier as CFString, 1, nil) else {
            throw IOError()
        }
        
        CGImageDestinationAddImage(dest, cgImage, metadata)
        
        if CGImageDestinationFinalize(dest) {
            return file
        }
        
        throw IOError()
    }
    
    /// Save the ``CGImage`` to a specified file, as a ``UTType``.
    /// - parameter file: file URL  to be saved into
    /// - parameter cgImage: the image to be saved
    /// - parameter utType: a ``UTType`` to identify the image format
    public func saveToFile(file: URL, cgImage: CGImage, utType: UTType) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(file as CFURL,
                                                         utType.identifier as CFString, 1, nil) else {
            throw IOError("Failed to create image destination")
        }
        
        CGImageDestinationAddImage(dest, cgImage, nil)
        
        if CGImageDestinationFinalize(dest) {
            return file
        }
        
        throw IOError("Failed to finalize")
    }
    
    /// Get the jpeg data from a ``CGImage``.
    /// - parameter cgImage: the image to get data
    public func getJpegData(cgImage: CGImage) throws -> Data {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw IOError("Error on getting data")
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            throw IOError("Error on finalize")
        }
        
        return mutableData as Data
    }
    
    /// Get the orientation from EXIF of the image ``file``.
    public func getExifOrientation(file: URL) -> CGImagePropertyOrientation {
        guard let map = getExifMap(file: file) else {
            return .up
        }
        guard let orientation = map["Orientation"] as? UInt32 else {
            return .up
        }
        return .init(rawValue: orientation) ?? .up
    }
    
    /// Get the creation date of the image ``file``.
    public func getCreationDate(file: URL) -> Date? {
        guard let exifMap = getExifMap(file: file)?["{Exif}"] as? Dictionary<String, Any> else {
            return nil
        }
        
        var creationDate: Date?
        
        if let date = exifMap["DateTimeOriginal"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            
            if let date = formatter.date(from: date) {
                creationDate = date
            } else {
                formatter.dateFormat = "yyyy:MM:dd hh:mm:ss"
                creationDate = formatter.date(from: date) ?? .now
            }
        }
        
        return creationDate
    }
    
    /// Get the exif map of the image ``file``.
    public func getExifMap(file: URL) -> Dictionary<String, Any>? {
        let options: [String: Any] = [
            kCGImageSourceShouldCacheImmediately as String: false,
        ]
        
        guard let source = CGImageSourceCreateWithURL(file as CFURL, options as CFDictionary) else {
            return nil
        }
        
        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
            return nil
        }
        
        guard let map = metadata as? Dictionary<String, Any> else {
            return nil
        }
        return map
    }
}
