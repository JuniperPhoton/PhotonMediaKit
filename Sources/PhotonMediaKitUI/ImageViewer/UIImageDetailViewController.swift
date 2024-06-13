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
    var onZoomChanged: ((ClosedRange<CGFloat>, CGFloat) -> Void)? = nil
    var onRequestDismiss: (() -> Void)? = nil
    var onSingleTap: (() -> Bool)? = nil
    var startFrame: CGRect = .zero
    private(set) var prefersHighDynamicRange: Bool = false
    
    private var loadTask: Task<(), Never>? = nil
    private var currentViewSize: CGSize = .zero
    private var originalScale: CGFloat = 1.0
    
    func setImage(_ asset: AssetProvider) {
        self.asset = asset
    }
    
    func setprefersHighDynamicRange(_ prefersHighDynamicRange: Bool) {
        self.prefersHighDynamicRange = prefersHighDynamicRange
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        scrollView.initialize()
        scrollView.setup()
        scrollView.imageContentMode = .aspectFit
        scrollView.initialOffset = .center
        
        // In stage manager, the view's bounds won't be updated until next render cycle.
        DispatchQueue.main.async { [self] in
            // We use the traditional frame method to layout the scrollView
            // Since it's resizing is based on the frame.
            scrollView.frame = self.view.bounds
            //scrollView.delegate = self

            showLoadingView()
            self.view.addSubview(scrollView)
            
            currentViewSize = self.view.frame.size
            
            if startFrame != .zero {
                loadImageForTransition()
            } else {
                loadFullImage()
            }
        }
    }
    
    @MainActor
    private func showLoadingView() {
        if loadingView.superview != nil {
            return
        }
        
        let superBounds = self.view.bounds
        let loadingViewBounds = loadingView.bounds
        
        if superBounds.isEmpty || loadingViewBounds.isEmpty {
            return
        }
        
        self.view.addSubview(loadingView)
        
        let x = superBounds.width / 2 - loadingViewBounds.width / 2
        let y = superBounds.height / 2 - loadingViewBounds.height / 2
        loadingView.frame = CGRect(x: x, y: y, width: loadingView.bounds.width, height: loadingView.bounds.height)
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
    
    func resetZoomScale() {
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
            
            guard let thumbnailImage = await MediaAssetLoader().fetchUIImage(
                phAsset: asset.phAssetRes.phAsset,
                option: .size(w: currentViewSize.width, h: currentViewSize.height),
                version: .current,
                prefersHighDynamicRange: false
            ) else {
                return
            }
            
            // While we displaying thumbnail image for transition, we start loading the full-size image at the same time.
            // This will help showing the full-size image more quickly
            async let fullSizeImageTask = preloadFullSizeImage(assetRes: asset, version: .current)
            
            // We use a thumbnail image as a placeholder during the transition
            await displayImageForTransition(uiImage: thumbnailImage, enableZoom: false)
            
            // By this point, the transition animation should be ended. Then we load the full size image.
            if let fullSizeImage = await fullSizeImageTask {
                displayImage(fullSizeImage: fullSizeImage, enableZoom: !asset.phAssetRes.isVideo)
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
                displayImage(fullSizeImage: fullSizeImage, enableZoom: true)
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
            await loadThenDisplayImage(
                assetRes: asset,
                option: .size(w: currentViewSize.width, h: currentViewSize.height),
                version: .current
            )
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
    
    private func preloadFullSizeImage(assetRes: AssetProvider, version: MediaAssetVersion) async -> UIImage? {
        return await MediaAssetLoader().fetchUIImage(
            phAsset: assetRes.phAssetRes.phAsset,
            option: .full,
            version: version,
            prefersHighDynamicRange: prefersHighDynamicRange
        )
    }
    
    @MainActor
    private func loadThenDisplayImage(
        assetRes: AssetProvider,
        option: MediaAssetLoader.FetchOption,
        version: MediaAssetVersion
    ) async {
        guard let fullSizeImage = await MediaAssetLoader().fetchUIImage(
            phAsset: assetRes.phAssetRes.phAsset,
            option: option,
            version: version,
            prefersHighDynamicRange: prefersHighDynamicRange
        ) else {
            return
        }
        
        displayImage(
            fullSizeImage: fullSizeImage,
            enableZoom: option == MediaAssetLoader.FetchOption.full && !assetRes.phAssetRes.isVideo
        )
        
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
    
    @MainActor
    private func displayImage(fullSizeImage: UIImage, enableZoom: Bool) {
        scrollView.display(image: fullSizeImage)
        scrollView.isUserInteractionEnabled = enableZoom
        loadingView.removeFromSuperview()
    }
    
    private func displayImageForTransition(uiImage: UIImage, enableZoom: Bool) async {
        return await withCheckedContinuation { continuation in
            let startBound = CGRect(x: 0, y: 0, width: startFrame.width, height: startFrame.height)
            let aspectRatioFrame = AVMakeRect(aspectRatio: uiImage.size, insideRect: startBound)
            
            scrollView.frame = startBound
            
            let originalTransform = scrollView.transform
            scrollView.transform = originalTransform.translatedBy(x: startFrame.minX, y: startFrame.minY)
            
            scrollView.display(image: uiImage)
            scrollView.isUserInteractionEnabled = enableZoom
            
            let animation = {
                let currentFrame = self.view.bounds
                let x = currentFrame.midX - self.startFrame.width / 2
                let y = currentFrame.midY - self.startFrame.height / 2
                
                let scaledX = currentFrame.width / aspectRatioFrame.width
                let scaledY = currentFrame.height / aspectRatioFrame.height
                
                self.scrollView.reconfigureImageSize()
                
                let scale = min(scaledX, scaledY)
                self.scrollView.transform = originalTransform.translatedBy(x: x, y: y).scaledBy(x: scale, y: scale)
            }
            
            let completion = {
                self.scrollView.transform = originalTransform
                self.scrollView.frame = self.view.bounds
                self.scrollView.reconfigureImageSize()
                
                continuation.resume()
            }
            
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                animation()
            } completion: { _ in
                completion()
            }
        }
    }
    
    // MARK: ImageScrollViewDelegate
    func imageScrollViewDidChangeOrientation(imageScrollView: UIImageScrollView) {
        // empty
    }
    
    func provideContentView(uiImage: UIImage) -> UIImageView? {
        let view = UIImageView(image: uiImage)
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            if uiImage.isHighDynamicRange {
                LibLogger.libDefault.log("set preferredImageDynamicRange to unspecified")
                view.preferredImageDynamicRange = .unspecified
            } else {
                LibLogger.libDefault.log("provideContentView")
            }
        }
        return view
    }
    
    func onSingleTap(imageScrollView: UIImageScrollView) -> Bool {
        return onSingleTap?() ?? false
    }
    
    func onDoubleTap(imageScrollView: UIImageScrollView) -> Bool {
        return false
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        DispatchQueue.main.async {
            self.onZoomChanged?(scrollView.minimumZoomScale...scrollView.maximumZoomScale, scrollView.zoomScale)
        }
    }
}
#endif
