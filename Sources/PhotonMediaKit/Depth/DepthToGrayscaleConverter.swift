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
import MetalPerformanceShaders

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
        
        guard let commandQueue = commandQueue else {
            return nil
        }
        
        guard let buffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
                
        guard let minMaxDest = create2x1MetalTexture(pixelFormat: inputTextureFormat, device: metalDevice) else {
            return nil
        }
        
        var min: Float = 0.0
        var max: Float = 0.0
                
        let minMax = MPSImageStatisticsMinAndMax(device: metalDevice)
        minMax.encode(
            commandBuffer: buffer,
            sourceTexture: inputTexture,
            destinationTexture: minMaxDest
        )
        
        buffer.commit()
        buffer.waitUntilCompleted()
        
        let result = getResult(format: inputTextureFormat, texture: minMaxDest)
        
        min = Float(result.min)
        max = Float(result.max)
                
        lowest = min
        highest = max
        range = DepthRenderParam(offset: lowest, range: highest - lowest)
        
        // Set up command queue, buffer, and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
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
    
    private func create2x1MetalTexture(
        pixelFormat: MTLPixelFormat,
        device: MTLDevice
    ) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = pixelFormat
        textureDescriptor.width = 2
        textureDescriptor.height = 1
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            print("Failed to create Metal texture")
            return nil
        }
        
        return texture
    }
    
    private func getStrideFor(format: MTLPixelFormat) -> Int? {
        if format == .r16Float {
            return MemoryLayout<Float16>.stride
        } else if format == .r32Float {
            return MemoryLayout<Float>.stride
        }
        
        return nil
    }
    
    private func getResult(format: MTLPixelFormat, texture: MTLTexture) -> (min: Float, max: Float) {
        var min: Float = 0.0
        var max: Float = 0.0
        
        if format == .r16Float {
            var minR16Float: Float16 = 0.0
            var maxR16Float: Float16 = 0.0
            getResult(texture: texture, min: &minR16Float, max: &maxR16Float)
            min = Float(minR16Float)
            max = Float(maxR16Float)
        } else if format == .r32Float {
            var minR32Float: Float = 0.0
            var maxR32Float: Float = 0.0
            getResult(texture: texture, min: &minR32Float, max: &maxR32Float)
            min = Float(minR32Float)
            max = Float(maxR32Float)
        }
        
        return (min, max)
    }
    
    private func getResult<T: FloatingPoint>(texture: MTLTexture, min: inout T, max: inout T) {
        var result = Array(repeating: T(0), count: 2)
        
        result.withUnsafeMutableBytes { buffer in
            if let pointer = buffer.baseAddress {
                texture.getBytes(
                    pointer,
                    bytesPerRow: 2 * 1 * MemoryLayout<T>.stride,
                    from: MTLRegion(origin: .init(x: 0, y: 0, z: 0), size: .init(width: 2, height: 1, depth: 1)),
                    mipmapLevel: 0
                )
            }
        }
        
        if let minValue = result[safeIndex: 0] {
            min = minValue
        }
        
        if let maxValue = result[safeIndex: 1] {
            max = maxValue
        }
    }
}
