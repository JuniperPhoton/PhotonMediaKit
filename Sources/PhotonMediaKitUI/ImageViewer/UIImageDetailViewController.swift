//
//  UIImageDetailViewController.swift
//  MyerTidy (iOS)
//
//  Created by Photon Juniper on 2023/1/6.
//

import Foundation
import AVFoundation
import AVKit
import Photos
import PhotonMediaKit
import CoreImage
import MetalKit
import SwiftUI

#if canImport(UIKit)
import UIKit

class UIImageDetailViewController<AssetProvider: MediaAssetProvider>: UIViewController, ImageScrollViewDelegate {
    private lazy var scrollView: UIImageScrollView = {
        let view = UIImageScrollView()
        view.imageScrollViewDelegate = self
        return view
    }()
    
    private lazy var loadingView: UIView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = UIColor.white.withAlphaComponent(0.3)
        view.startAnimating()
        return view
    }()
    
    private lazy var playButton: UIImageView = {
        let button = UIImageView()
        button.image = UIImage(systemName: "play.circle.fill")
        button.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTapPlayButton)))
        button.isUserInteractionEnabled = true
        button.tintColor = .white
        return button
    }()
    
    var asset: AssetProvider? = nil
    var onZoomChanged: ((CGFloat) -> Void)? = nil
    var onRequestDismiss: (() -> Void)? = nil
    var startFrame: CGRect = .zero
    private(set) var useDynamicRange: Bool = false
    
    private var loadTask: Task<(), Never>? = nil
    private var currentViewSize: CGSize = .zero
    private var originalScale: CGFloat = 1.0
    
    func setImage(_ asset: AssetProvider) {
        self.asset = asset
    }
    
    func setUseDynamicRange(_ useDynamicRange: Bool) {
        self.useDynamicRange = useDynamicRange
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        scrollView.initialize()
        scrollView.setup()
        scrollView.imageContentMode = .aspectFit
        scrollView.initialOffset = .center
        
        // We use the traditional frame method to layout the scrollView
        // Since it's resizing is based on the frame.
        scrollView.frame = self.view.bounds
        
        self.view.addSubview(loadingView)
        self.view.addSubview(scrollView)
        
        // Disable autoresizing mask translation for loadingView
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Define constraints to pin loadingView to all edges of its superview
        if let superview = loadingView.superview {
            NSLayoutConstraint.activate([
                loadingView.topAnchor.constraint(equalTo: superview.topAnchor),
                loadingView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                loadingView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                loadingView.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
            ])
        }
        
        currentViewSize = self.view.frame.size
        
        if startFrame != .zero {
            loadImageForTransition()
        } else {
            loadFullImage()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelLoadingImage()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        currentViewSize = size
        
        // We use the traditional frame method to layout the scrollView
        // Since it's resizing is based on the frame. We update its frame on the new size
        // Note that at this point, self.view's bounds is not updated yet.
        self.scrollView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }
    
    func reset() {
        self.scrollView.zoomScale = self.scrollView.minimumZoomScale
    }
    
    func loadImageForTransition() {
        Task {
            guard let asset = asset else {
                return
            }
            if self.scrollView.subviews.count > 0 {
                return
            }
            
            guard let thumbnailImage = await MediaAssetLoader().fetchThumbnailCGImage(
                phAsset: asset.phAssetRes.phAsset,
                size: currentViewSize
            ) else {
                return
            }
            
            // While we displaying thumbnail image for transition, we start loading the full-size image at the same time.
            // This will help showing the full-size image more quickly
            async let fullSizeImageTask = preloadFullSizeImage(assetRes: asset, version: .current)
            
            // We use a thumbnail image as a placeholder during the transition
            await displayImageForTransition(image: CIImage(cgImage: thumbnailImage), enableZoom: false)
            
            // By this point, the transition animation should be ended. Then we load the full size image.
            if let fullSizeImage = await fullSizeImageTask {
                displayImage(image: fullSizeImage, enableZoom: !asset.phAssetRes.isVideo)
                configureForMediaType()
            }
        }
    }
    
    func loadImageProgressively() {
        guard let asset = asset else {
            return
        }
        if self.scrollView.subviews.count > 0 {
            return
        }
        
        loadTask = Task {
            self.scrollView.alpha = 0.0
            
            // While we displaying thumbnail, we start loading the full-size image at the same time.
            // This will help showing the full-size image more quickly
            async let fullSizeImageTask = preloadFullSizeImage(assetRes: asset, version: .current)
            
            await loadThenDisplayImage(assetRes: asset,
                                       option: .size(w: currentViewSize.width, h: currentViewSize.height), version: .current)
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.scrollView.alpha = 1.0
            }
            
            if let fullSizeImage = await fullSizeImageTask {
                displayImage(image: fullSizeImage, enableZoom: true)
                configureForMediaType()
            }
            
            loadTask = nil
        }
    }
    
    private func loadPlaceholderImage() {
        guard let asset = asset else {
            return
        }
        
        loadTask?.cancel()
        loadTask = Task {
            await loadThenDisplayImage(assetRes: asset,
                                       option: .size(w: currentViewSize.width, h: currentViewSize.height), version: .current)
            loadTask = nil
        }
    }
    
    private func loadFullImage() {
        guard let asset = asset else {
            return
        }
        
        loadTask?.cancel()
        loadTask = Task {
            await loadThenDisplayImage(assetRes: asset, option: .full, version: .current)
            loadTask = nil
        }
    }
    
    func cancelLoadingImage() {
        loadTask?.cancel()
        loadTask = nil
        setupAVViewControllerTask?.cancel()
    }
    
    /// Get a frame where image will be positioned when its in the minimum zoom scale, which is also the same frame when the user first
    /// enter this ``UIImageDetailViewController``.
    func getAspectRatioFitImageFrame() -> CGRect? {
        let imageSize = scrollView.imageSize
        if imageSize == .zero {
            return nil
        }
        let rect = AVMakeRect(aspectRatio: imageSize, insideRect: self.view.bounds)
        return rect
    }
    
    private func preloadFullSizeImage(assetRes: AssetProvider, version: MediaAssetVersion) async -> CIImage? {
        guard let cgImage = await MediaAssetLoader().fetchFullCGImage(phAsset: assetRes.phAssetRes.phAsset) else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }
    
    private func loadThenDisplayImage(assetRes: AssetProvider,
                                      option: MediaAssetLoader.FetchOption,
                                      version: MediaAssetVersion) async {
        guard let cgImage = await MediaAssetLoader().fetchFullCGImage(phAsset: assetRes.phAssetRes.phAsset) else {
            return
        }
        let ciImage = CIImage(cgImage: cgImage)
        displayImage(image: ciImage, enableZoom: option == MediaAssetLoader.FetchOption.full && !assetRes.phAssetRes.isVideo)
        configureForMediaType()
    }
    
    private var avPlayerViewController: CustomAVVideoPlayerController? = nil
    private var setupAVViewControllerTask: Task<Void, Never>? = nil
    
    private func configureForMediaType() {
        guard let assetRes = self.asset else {
            return
        }
        
        if assetRes.phAssetRes.isVideo {
            let playButton = playButton
            if playButton.superview == nil {
                playButton.alpha = 0.0
                
                self.view.addSubview(playButton)
                
                // Disable autoresizing mask translation for playButton
                playButton.translatesAutoresizingMaskIntoConstraints = false
                
                // Define constraints to set the size and center the playButton
                NSLayoutConstraint.activate([
                    playButton.widthAnchor.constraint(equalToConstant: 100),
                    playButton.heightAnchor.constraint(equalToConstant: 100),
                    playButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                    playButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
                ])
                
                // Animate the playButton's alpha to fade it in
                UIView.animate(withDuration: 0.3) {
                    playButton.alpha = 1.0
                }
            }
        } else {
            // Remove playButton from its superview
            playButton.removeFromSuperview()
        }
    }
    
    @objc
    private func onTapPlayButton() {
        setupAVViewControllerTask = Task { @MainActor in
            guard let asset = asset?.phAssetRes.phAsset else {
                return
            }
            
            if avPlayerViewController == nil {
                await setupAVPlayerController(asset: asset)
            }
            
            if let vc = avPlayerViewController {
                vc.play()
                self.present(vc, animated: true)
            } else {
                showCannotPlayVideoAlert()
            }
        }
    }
    
    private func setupAVPlayerController(asset: PHAsset) async {
        guard let avAsset = (await MediaAssetLoader().requestAVAsset(phAsset: asset, version: .current, isNetworkAccessAllowed: false) { _ in
            // ignored
        }) else {
            return
        }
        
        avPlayerViewController = CustomAVVideoPlayerController()
        avPlayerViewController?.setupPlayer(avAsset: avAsset)
    }
    
    private func showCannotPlayVideoAlert() {
        let alertController = UIAlertController(
            title: "AlertCantPlayVideoTitle".localized(),
            message: "AlertCantPlayVideoMessage".localized(),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "IKnowAction".localized(), style: .default))
        self.present(alertController, animated: true)
    }
    
    private func displayImage(image: CIImage, enableZoom: Bool) {
        scrollView.display(image: image)
        scrollView.isUserInteractionEnabled = enableZoom
    }
    
    private func displayImageForTransition(image: CIImage, enableZoom: Bool) async {
        return await withCheckedContinuation { continuation in
            let startBound = CGRect(x: 0, y: 0, width: startFrame.width, height: startFrame.height)
            let aspectRatioFrame = AVMakeRect(aspectRatio: image.extent.size, insideRect: startBound)
            
            scrollView.frame = startBound
            
            let originalTransform = scrollView.transform
            scrollView.transform = originalTransform.translatedBy(x: startFrame.minX, y: startFrame.minY)
            
            scrollView.display(image: image)
            scrollView.isUserInteractionEnabled = enableZoom
            
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                let currentFrame = self.view.bounds
                let x = currentFrame.midX - self.startFrame.width / 2
                let y = currentFrame.midY - self.startFrame.height / 2
                
                let scaledX = currentFrame.width / aspectRatioFrame.width
                let scaledY = currentFrame.height / aspectRatioFrame.height
                
                self.scrollView.reconfigureImageSize()
                
                let scale = min(scaledX, scaledY)
                self.scrollView.transform = originalTransform.translatedBy(x: x, y: y).scaledBy(x: scale, y: scale)
            } completion: { success in
                self.scrollView.transform = originalTransform
                self.scrollView.frame = self.view.bounds
                self.scrollView.reconfigureImageSize()
                
                continuation.resume()
            }
        }
    }
    
    // MARK: ImageScrollViewDelegate
    func imageScrollViewDidChangeOrientation(imageScrollView: UIImageScrollView) {
        // empty
    }
    
    private let renderer: MetalRenderer = {
        return MetalRenderer()
    }()
    
    func provideContentView(image: CIImage) -> (UIView & UIImageHolderView)? {
        let enableSetNeedsDisplay = false
        
        renderer.initializeCIContext(colorSpace: nil, name: "detail")
        
        renderer.requestChanged(displayedImage: image)
        
        let view = BoundAwareMTKView(frame: .zero, device: renderer.device)
        view.onBoundsChanged = { [weak view] bounds in
            if enableSetNeedsDisplay {
                view?.setNeedsDisplay(bounds)
            }
        }
        
        view.imageToDisplay = image
        
        if enableSetNeedsDisplay {
            view.enableSetNeedsDisplay = true
            view.isPaused = true
        } else {
            // Suggest to Core Animation, through MetalKit, how often to redraw the view.
            view.preferredFramesPerSecond = 30
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
        
        // Allow Core Image to render to the view using the Metal compute pipeline.
        view.framebufferOnly = false
        view.delegate = renderer
        
        if let layer = view.layer as? CAMetalLayer {
            layer.isOpaque = false
        }
        
        return view
    }
    
    func onSingleTap(imageScrollView: UIImageScrollView) -> Bool {
        return false
    }
    
    func onDoubleTap(imageScrollView: UIImageScrollView) -> Bool {
        return false
    }
}
#endif


private class BoundAwareMTKView: MTKView, UIImageHolderView {
    private var currentBounds: CGRect = .zero
    
    var onBoundsChanged: ((CGRect) -> Void)? = nil
    
    var imageToDisplay: CIImage? = nil
    
#if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if self.currentBounds != self.bounds {
            self.currentBounds = self.bounds
            onBoundsChanged?(self.currentBounds)
        }
    }
#else
    override func layout() {
        super.layout()
        
        if self.currentBounds != self.bounds {
            self.currentBounds = self.bounds
            onBoundsChanged?(self.currentBounds)
        }
    }
#endif
}

private let maxBuffersInFlight = 3

public final class MetalRenderer: NSObject, MTKViewDelegate, ObservableObject {
    @Published var requestedDisplayedTime = CFAbsoluteTimeGetCurrent()
    
    public let device: MTLDevice
    
    let commandQueue: MTLCommandQueue
    var ciContext: CIContext? = nil
    var opaqueBackground: CIImage
    let startTime: CFAbsoluteTime
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var scaleToFill: Bool = false
    
    private var displayedImage: CIImage? = nil
    
    public override init() {
        let start = CFAbsoluteTimeGetCurrent()
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        self.opaqueBackground = CIImage.black
        
        self.startTime = CFAbsoluteTimeGetCurrent()
        
        debugPrint("MetalRenderer init \(CFAbsoluteTimeGetCurrent() - start)s")
        super.init()
    }
    
    /// The the background color to be composited with.
    /// If the color is not opaque, please remember to set ``isOpaque`` in ``MetalView``.
    public func setBackgroundColor(ciColor: CIColor) {
        self.opaqueBackground = CIImage(color: ciColor)
    }
    
    public func setScaleToFill(scaleToFill: Bool) {
        self.scaleToFill = scaleToFill
    }
    
    /// Initialize the CIContext with a specified working ``CGColorSpace``.
    public func initializeCIContext(colorSpace: CGColorSpace?, name: String) {
        let start = CFAbsoluteTimeGetCurrent()
        
        // Set up the Core Image context's options:
        // - Name the context to make CI_PRINT_TREE debugging easier.
        // - Disable caching because the image differs every frame.
        // - Allow the context to use the low-power GPU, if available.
        var options = [CIContextOption: Any]()
        options = [
            .name: name,
            .cacheIntermediates: false,
            .allowLowPower: true,
        ]
        if let colorSpace = colorSpace {
            options[.workingColorSpace] = colorSpace
        }
        self.ciContext = CIContext(
            mtlCommandQueue: self.commandQueue,
            options: options
        )
        
        debugPrint("MetalRenderer initializeCIContext \(CFAbsoluteTimeGetCurrent() - start)s, name: \(name) to color space: \(String(describing: colorSpace))")
    }
    
    /// Request update the image.
    public func requestChanged(displayedImage: CIImage?) {
        self.displayedImage = displayedImage
        self.requestedDisplayedTime = CFAbsoluteTimeGetCurrent()
    }
    
    /// - Tag: draw
    public func draw(in view: MTKView) {
        guard let ciContext = ciContext else {
            debugPrint("CIContext is nil!")
            return
        }
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            // Add a completion handler that signals `inFlightSemaphore` when Metal and the GPU have fully
            // finished processing the commands that the app encoded for this frame.
            // This completion indicates that Metal and the GPU no longer need the dynamic buffers that
            // Core Image writes to in this frame.
            // Therefore, the CPU can overwrite the buffer contents without corrupting any rendering operations.
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            if let drawable = view.currentDrawable {
                let dSize = view.drawableSize
                
                // Create a destination the Core Image context uses to render to the drawable's Metal texture.
                let destination = CIRenderDestination(
                    width: Int(dSize.width),
                    height: Int(dSize.height),
                    pixelFormat: view.colorPixelFormat,
                    commandBuffer: nil
                ) {
                    return drawable.texture
                }
                
                // Create a displayable image for the current time.
                guard var image = self.displayedImage else {
                    return
                }
                
                let scaleW = min(1.0, CGFloat(dSize.width) / image.extent.width)
                let scaleH = min(1.0, CGFloat(dSize.height) / image.extent.height)
                
                // To perfrom scaledToFit, use min. Use max for scaledToFill effect.
                let scale: CGFloat
                if scaleToFill {
                    scale = max(scaleW, scaleH)
                } else {
                    scale = min(scaleW, scaleH)
                }
                
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                
                // Center the image in the view's visible area.
                let iRect = image.extent
                var backBounds = CGRect(x: 0, y: 0, width: dSize.width, height: dSize.height)
                
                let shiftX: CGFloat
                let shiftY: CGFloat
                
                shiftX = round((backBounds.size.width + iRect.origin.x - iRect.size.width) * 0.5)
                shiftY = round((backBounds.size.height + iRect.origin.y - iRect.size.height) * 0.5)
                
                // Read the center port of the image.
                backBounds = backBounds.offsetBy(dx: -shiftX, dy: -shiftY)
                
                // Blend the image over an opaque background image.
                // This is needed if the image is smaller than the view, or if it has transparent pixels.
                image = image.composited(over: self.opaqueBackground)
                
                // Start a task that renders to the texture destination.
                _ = try? ciContext.startTask(
                    toRender: image,
                    from: backBounds,
                    to: destination,
                    at: .zero
                )
                
                // Insert a command to present the drawable when the buffer has been scheduled for execution.
                commandBuffer.present(drawable)
                
                // Commit the command buffer so that the GPU executes the work that the Core Image Render Task issues.
                commandBuffer.commit()
            }
        }
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Respond to drawable size or orientation changes.
    }
}
