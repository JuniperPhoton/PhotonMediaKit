//
//  GrayscaleToDepthConverter.swift
//  PhotonCam
//
//  Created by Photon Juniper on 2024/3/22.
//

import CoreMedia
import CoreVideo
import Metal
import AVFoundation
import CoreImage

/// The main target should contain the implementation of GrayscaleToDepth+Native.metal
public class GrayscaleToDepthConverter {
    let description: String = "Grayscale to Depth Converter"
    
    var isPrepared = false
    
    private let metalDevice = MTLCreateSystemDefaultDevice()!
    
    private var computePipelineState: MTLComputePipelineState?
    
    private lazy var commandQueue: MTLCommandQueue? = {
        return self.metalDevice.makeCommandQueue()
    }()
    
    private var textureCache: CVMetalTextureCache!
    
    public required init() {
        let url = Bundle.main.url(forResource: "GrayscaleToDepth+Native", withExtension: "metallib")!
        let defaultLibrary = try! metalDevice.makeLibrary(URL: url)
        let kernelFunction = defaultLibrary.makeFunction(name: "grayscaleToDepth")
        do {
            computePipelineState = try metalDevice.makeComputePipelineState(function: kernelFunction!)
        } catch {
            fatalError("Unable to create depth converter pipeline state. (\(error))")
        }
    }
    
    public func prepare() {
        if isPrepared {
            return
        }
        
        reset()
        
        var metalTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
            print("Unable to allocate depth converter texture cache")
        } else {
            textureCache = metalTextureCache
        }
        
        isPrepared = true
    }
    
    public func reset() {
        textureCache = nil
        isPrepared = false
    }
    
    private func createOutputPixelBuffer(input: CVPixelBuffer, targetCVPixelFormat: OSType) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey as String: kCFBooleanTrue!
        ] as CFDictionary
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(width),
            Int(height),
            targetCVPixelFormat,
            attributes,
            &pixelBuffer
        )
        return pixelBuffer
    }
    
    /// Convert the input grayscale BGRA8 ``CVPixelBuffer`` to the target disparity map.
    public func render(input: CVPixelBuffer, targetCVPixelFormat: OSType) -> CVPixelBuffer? {
        if !isPrepared {
            print("Invalid state: Not prepared")
            return nil
        }
        
        guard let targetFormat = PixelFormatUtils.shared.getMetalFormatForDepth(cvPixelFormat: targetCVPixelFormat) else {
            print("Invalid state: format not supported")
            return nil
        }
        
        guard let outputPixelBuffer = createOutputPixelBuffer(input: input, targetCVPixelFormat: targetCVPixelFormat) else {
            print("Allocation failure: Could not get pixel buffer from pool (\(self.description))")
            return nil
        }
        
        guard let inputTexture = MetalUtils.shared.makeTextureFromCVPixelBuffer(
            pixelBuffer: input,
            textureFormat: .bgra8Unorm,
            textureCache: textureCache
        ) else {
            print("failed to make inputTexture")
            return nil
        }
        
        guard let outputTexture = MetalUtils.shared.makeTextureFromCVPixelBuffer(
            pixelBuffer: outputPixelBuffer,
            textureFormat: targetFormat,
            textureCache: textureCache
        ) else {
            print("failed to make outputTexture")
            return nil
        }
        
        // Set up command queue, buffer, and encoder
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create Metal command queue")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return nil
        }
        
        commandEncoder.label = "Grayscale to Depth"
        commandEncoder.setComputePipelineState(computePipelineState!)
        commandEncoder.setTexture(inputTexture, index: 0)
        commandEncoder.setTexture(outputTexture, index: 1)
        
        // Set up the thread groups.
        let width = computePipelineState!.threadExecutionWidth
        let height = computePipelineState!.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
        let threadgroupsPerGrid = MTLSize(width: (inputTexture.width + width - 1) / width,
                                          height: (inputTexture.height + height - 1) / height,
                                          depth: 1)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        return outputPixelBuffer
    }
}
