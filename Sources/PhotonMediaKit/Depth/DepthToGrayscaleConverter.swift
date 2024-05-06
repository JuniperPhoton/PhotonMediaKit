//
//  File.swift
//
//
//  Created by Photon Juniper on 2024/3/23.
//
import CoreMedia
import CoreVideo
import Metal
import AVFoundation
import CoreImage
import PhotonMediaKitObjc

/// Copy from AVCamFilter example from Apple.
/// The main target should contain the implementation of DepthToGrayscale+Native.metal
public class DepthToGrayscaleConverter {
    let description: String = "Depth to Grayscale Converter"
    
    public private(set) var isPrepared = false
    
    private(set) var inputFormatDescription: CMFormatDescription?
    
    private(set) var outputFormatDescription: CMFormatDescription?
    
    private var inputTextureFormat: MTLPixelFormat = .invalid
    
    private var outputPixelBufferPool: CVPixelBufferPool!
    
    private let metalDevice = MTLCreateSystemDefaultDevice()!
    
    private var computePipelineState: MTLComputePipelineState?
    
    private lazy var commandQueue: MTLCommandQueue? = {
        return self.metalDevice.makeCommandQueue()
    }()
    
    private var textureCache: CVMetalTextureCache!
    
    private var lowest: Float = 0.0
    private var highest: Float = 8.0
    
    struct DepthRenderParam {
        var offset: Float
        var range: Float
    }
    
    var range: DepthRenderParam = DepthRenderParam(offset: 0.0, range: 8.0)
    
    public required init() {
        let url = Bundle.main.url(forResource: "DepthToGrayscale+Native", withExtension: "metallib")!
        let defaultLibrary = try! metalDevice.makeLibrary(URL: url)
        let kernelFunction = defaultLibrary.makeFunction(name: "depthToGrayscale")
        do {
            computePipelineState = try metalDevice.makeComputePipelineState(function: kernelFunction!)
        } catch {
            fatalError("Unable to create depth converter pipeline state. (\(error))")
        }
    }
    
    public func getPreparedInputFormatDescription() -> CMFormatDescription? {
        return inputFormatDescription
    }
    
    public func getGrayscaleImage(depthDataMap: CVPixelBuffer) -> CIImage? {
        if !self.isPrepared {
            var depthFormatDescription: CMFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: depthDataMap,
                formatDescriptionOut: &depthFormatDescription
            )
            if let unwrappedDepthFormatDescription = depthFormatDescription {
                self.prepare(with: unwrappedDepthFormatDescription, outputRetainedBufferCountHint: 2)
            }
        }
        
        guard let depthPixelBuffer = self.render(pixelBuffer: depthDataMap) else {
            return nil
        }
        
        return CIImage(cvPixelBuffer: depthPixelBuffer)
    }
    
    public func prepare(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
        reset()
        
        outputPixelBufferPool = MetalUtils.shared.allocateOutputBuffers(
            with: formatDescription,
            outputRetainedBufferCountHint: outputRetainedBufferCountHint
        )
        if outputPixelBufferPool == nil {
            return
        }
        
        var pixelBuffer: CVPixelBuffer?
        var pixelBufferFormatDescription: CMFormatDescription?
        _ = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &pixelBuffer)
        if let pixelBuffer = pixelBuffer {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &pixelBufferFormatDescription
            )
        }
        pixelBuffer = nil
        
        inputFormatDescription = formatDescription
        outputFormatDescription = pixelBufferFormatDescription
        
        let inputMediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        if let format = PixelFormatUtils.shared.getMetalFormatForDepth(cvPixelFormat: inputMediaSubType) {
            inputTextureFormat = format
        }
        
        var metalTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
            print("Unable to allocate depth converter texture cache")
        } else {
            textureCache = metalTextureCache
        }
        
        isPrepared = true
    }
    
    public func reset() {
        outputPixelBufferPool = nil
        outputFormatDescription = nil
        inputFormatDescription = nil
        textureCache = nil
        isPrepared = false
    }
    
    // MARK: - Depth to Grayscale Conversion
    public func render(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        if !isPrepared {
            print("Invalid state: Not prepared")
            return nil
        }
        
        var newPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newPixelBuffer)
        guard let outputPixelBuffer = newPixelBuffer else {
            print("Allocation failure: Could not get pixel buffer from pool (\(self.description))")
            return nil
        }
        
        guard let outputTexture = MetalUtils.shared.makeTextureFromCVPixelBuffer(
            pixelBuffer: outputPixelBuffer,
            textureFormat: .bgra8Unorm,
            textureCache: textureCache
        ) else {
            return nil
        }
        
        guard let inputTexture = MetalUtils.shared.makeTextureFromCVPixelBuffer(
            pixelBuffer: pixelBuffer,
            textureFormat: inputTextureFormat,
            textureCache: textureCache
        ) else {
            return nil
        }
        
        var min: Float = 0.0
        var max: Float = 0.0
        minMaxFromPixelBuffer(pixelBuffer, &min, &max, inputTextureFormat)
        lowest = min
        highest = max
        range = DepthRenderParam(offset: lowest, range: highest - lowest)
        
        // Set up command queue, buffer, and encoder
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create Metal command queue")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return nil
        }
        
        commandEncoder.label = "Depth to Grayscale"
        commandEncoder.setComputePipelineState(computePipelineState!)
        commandEncoder.setTexture(inputTexture, index: 0)
        commandEncoder.setTexture(outputTexture, index: 1)
        withUnsafeMutablePointer(to: &range) { rangeRawPointer in
            commandEncoder.setBytes(rangeRawPointer, length: MemoryLayout<DepthRenderParam>.size, index: 0)
        }
        
        // Set up the thread groups.
        let width = computePipelineState!.threadExecutionWidth
        let height = computePipelineState!.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadGroup = MTLSizeMake(width, height, 1)
        let threadGroupsPerGrid = MTLSize(width: (inputTexture.width + width - 1) / width,
                                          height: (inputTexture.height + height - 1) / height,
                                          depth: 1)
        commandEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()        
        commandBuffer.waitUntilCompleted()
        
        return outputPixelBuffer
    }
}
