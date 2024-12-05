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
import PhotosUI

#if canImport(UIKit)
import UIKit

class UIImageDetailViewController<AssetProvider: MediaAssetProvider>: UIViewController, ImageScrollViewDelegate, PHLivePhotoViewDelegate {
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
    
    private var livePhotoView: PHLivePhotoView? = nil
    
    var asset: AssetProvider? = nil
    var onZoomChanged: ((ClosedRange<CGFloat>, CGFloat) -> Void)? = nil
    var onRequestDismiss: (() -> Void)? = nil
    var startFrame: CGRect = .zero
    var isAnimating = false
    private(set) var prefersHighDynamicRange: Bool = false
    private(set) var version: MediaAssetVersion = .current

    private var loadTask: Task<(), Never>? = nil
    private var currentViewSize: CGSize = .zero
    private var originalScale: CGFloat = 1.0
    private var requestId: PHImageRequestID? = nil
    private var livePhoto: PHLivePhoto? = nil
    
    func setImage(_ asset: AssetProvider) {
        self.asset = asset
    }
    
    func setAnimating(_ animating: Bool) {
        self.isAnimating = animating
        if !animating {
            playLivePhotoView(playbackStyle: .hint)
        } else {
            //hideLivePhotoView()
        }
    }
    
    func setPrefersHighDynamicRange(_ prefersHighDynamicRange: Bool) {
        self.prefersHighDynamicRange = prefersHighDynamicRange
    }
    
    func setVersion(_ version: MediaAssetVersion) {
        self.version = version
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let action = { [weak self] in
            guard let self = self else { return }
            
            scrollView.initialize()
            scrollView.setup()
            scrollView.imageContentMode = .aspectFit
            scrollView.initialOffset = .center
            scrollView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(onLongPress)))
            
            // We use the traditional frame method to layout the scrollView
            // Since it's resizing is based on the frame.
            scrollView.frame = self.view.bounds
            //scrollView.delegate = self
            
            showLoadingView()
            self.view.addSubview(scrollView)
            
            currentViewSize = self.view.frame.size
            
            loadImageForTransition()
        }
        
        if self.view.bounds.isEmpty {
            // In stage manager, the view's bounds won't be updated until next render cycle.
            DispatchQueue.main.async {
                action()
            }
        } else {
            action()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tryShowLivePhotoView(playbackStyle: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancelLoadingImage()
        hideLivePhotoView()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        currentViewSize = size
        
        // We use the traditional frame method to layout the scrollView
        // Since it's resizing is based on the frame. We update its frame on the new size
        // Note that at this point, self.view's bounds is not updated yet.
        self.scrollView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        
        if let livePhotoView = livePhotoView, livePhotoView.superview != nil {
            layoutLivePhotoView()
        }
    }
    
    @objc
    private func onLongPress(gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            tryShowLivePhotoView(playbackStyle: .full)
        } else if gesture.state == .ended {
            hideLivePhotoView()
        }
    }
    
    // MARK: Live Photo
    func tryShowLivePhotoView(playbackStyle: PHLivePhotoViewPlaybackStyle?) {
        guard let asset = asset?.phAssetRes.phAsset else {
            return
        }
        
        if self.scrollView.superview == nil {
            return
        }
        
        if asset.isLivePhotoSubType() {
            if let livePhoto = self.livePhoto {
                showLivePhotoView(photo: livePhoto, playbackStyle: playbackStyle)
            } else {
                let options = PHLivePhotoRequestOptions()
                options.version = version.getPHImageRequestOptionsVersion()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = false
                
                print("asset size \(asset.pixelSize)")
                
                requestId = PHImageManager.default().requestLivePhoto(
                    for: asset,
                    targetSize: asset.pixelSize,
                    contentMode: .aspectFit,
                    options: options
                ) { [weak self] photo, dic in
                    guard let self = self else { return }
                    
                    if let photo = photo {
                        self.livePhoto = photo
                        showLivePhotoView(photo: photo, playbackStyle: playbackStyle)
                    }
                }
            }
        }
    }
    
    private func playLivePhotoView(playbackStyle: PHLivePhotoViewPlaybackStyle) {
        guard let livePhotoView = livePhotoView else {
            return
        }
        
        if livePhotoView.superview == nil {
            return
        }
        
        livePhotoView.startPlayback(with: playbackStyle)
    }
    
    private func showLivePhotoView(photo: PHLivePhoto, playbackStyle: PHLivePhotoViewPlaybackStyle?) {
        guard let innerView = self.scrollView.subviews.last else {
            return
        }
        
        tryInitializeLivePhotoView()
        
        guard let livePhotoView = livePhotoView else {
            return
        }
        
        if livePhotoView.superview == nil {
            livePhotoView.livePhoto = photo
            innerView.addSubview(livePhotoView)
        }
        
        layoutLivePhotoView()
        
        if !isAnimating, let playbackStyle = playbackStyle {
            livePhotoView.startPlayback(with: playbackStyle)
        }
    }
    
    private func layoutLivePhotoView() {
        guard let livePhotoView = livePhotoView else {
            return
        }
        
        guard let livePhoto = livePhotoView.livePhoto else {
            return
        }
        
        guard let innerView = self.scrollView.subviews.last else {
            return
        }
        
        let size = livePhoto.size
        let fitRect = innerView.bounds.largestAspectFitRect(of: size)
        
        livePhotoView.frame = fitRect
    }
    
    @MainActor
    private func tryInitializeLivePhotoView() {
        if livePhotoView == nil {
            let livePhotoView = PHLivePhotoView()
            livePhotoView.delegate = self
            self.livePhotoView = livePhotoView
        }
    }
    
    private func hideLivePhotoView() {
        guard let livePhotoView = livePhotoView else {
            return
        }
        
        if livePhotoView.superview != nil {
            livePhotoView.stopPlayback()
            livePhotoView.removeFromSuperview()
        }
        if let id = requestId {
            PHImageManager.default().cancelImageRequest(id)
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
    
    func resetZoomScale() {
        self.scrollView.zoomScale = self.scrollView.minimumZoomScale
    }
    
    private func loadImageForTransition() {
        guard let asset = asset else {
            return
        }
        
        if self.scrollView.subviews.count > 0 {
            return
        }
        
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            
            let size = currentViewSize
            
            var thumbnailImage = await MediaAssetLoader().fetchUIImage(
                phAsset: asset.phAssetRes.phAsset,
                option: .size(w: size.width, h: size.height),
                version: version,
                prefersHighDynamicRange: false
            )
            
            if thumbnailImage == nil && version == .original {
                thumbnailImage = await MediaAssetLoader().fetchUIImage(
                    phAsset: asset.phAssetRes.phAsset,
                    option: .size(w: size.width, h: size.height),
                    version: .current,
                    prefersHighDynamicRange: false
                )
            }
            
            guard let thumbnailImage else {
                return
            }
            
            if Task.isCancelled {
                LibLogger.libDefault.warning("loadImageForTransition, task cancelled")
                return
            }
            
            // While we displaying thumbnail image for transition, we start loading the full-size image at the same time.
            // This will help showing the full-size image more quickly
            async let fullSizeImageTask = preloadFullSizeImage(assetRes: asset, version: version)
            
            // We use a thumbnail image as a placeholder during the transition
            await displayImageForTransition(uiImage: thumbnailImage, enableZoom: false)
            
            if Task.isCancelled {
                LibLogger.libDefault.warning("loadImageForTransition, task cancelled")
                return
            }
            
            // By this point, the transition animation should be ended. Then we load the full size image.
            if let fullSizeImage = await fullSizeImageTask {
                displayFullSizeImage(fullSizeImage: fullSizeImage, enableZoom: !asset.phAssetRes.isVideo)
                configureForMediaType()
            }
        }
    }
    
    func cancelLoadingImage() {
        loadTask?.cancel()
        loadTask = nil
        setupAVViewControllerTask?.cancel()
        
        if let requestId = requestId {
            PHImageManager.default().cancelImageRequest(requestId)
        }
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
        var image = await MediaAssetLoader().fetchUIImage(
            phAsset: assetRes.phAssetRes.phAsset,
            option: .full,
            version: version,
            prefersHighDynamicRange: prefersHighDynamicRange
        )
        
        if image == nil && version == .original {
            image = await MediaAssetLoader().fetchUIImage(
                phAsset: assetRes.phAssetRes.phAsset,
                option: .full,
                version: .current,
                prefersHighDynamicRange: prefersHighDynamicRange
            )
        }
        
        return image
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
        
        displayFullSizeImage(
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
        guard let avAsset = (await MediaAssetLoader().requestAVAsset(phAsset: asset, version: version, isNetworkAccessAllowed: false) { _ in
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
    private func displayFullSizeImage(fullSizeImage: UIImage, enableZoom: Bool) {
        guard let asset = asset?.phAssetRes.phAsset else {
            return
        }
        
        scrollView.display(image: fullSizeImage, animateChanges: !asset.isLivePhotoSubType())
        scrollView.isUserInteractionEnabled = enableZoom
        loadingView.removeFromSuperview()
        tryShowLivePhotoView(playbackStyle: nil)
    }
    
    private func displayImageForTransition(uiImage: UIImage, enableZoom: Bool) async {
        return await withCheckedContinuation { [weak self] continuation in
            guard let self = self else { return }
            
            let scrollView = self.scrollView
            
            if startFrame.isEmpty {
                scrollView.display(image: uiImage, animateChanges: false)
                scrollView.isUserInteractionEnabled = enableZoom
                scrollView.reconfigureImageSize()
                continuation.resume()
            } else {
                let startBound = CGRect(x: 0, y: 0, width: startFrame.width, height: startFrame.height)
                let aspectRatioFrame = AVMakeRect(aspectRatio: uiImage.size, insideRect: startBound)
                
                scrollView.frame = startBound
                
                let originalTransform = scrollView.transform
                scrollView.transform = originalTransform.translatedBy(x: startFrame.minX, y: startFrame.minY)
                
                scrollView.display(image: uiImage, animateChanges: false)
                scrollView.isUserInteractionEnabled = enableZoom
                
                let animation = {
                    let currentFrame = self.view.bounds
                    let x = currentFrame.midX - self.startFrame.width / 2
                    let y = currentFrame.midY - self.startFrame.height / 2
                    
                    let scaledX = currentFrame.width / aspectRatioFrame.width
                    let scaledY = currentFrame.height / aspectRatioFrame.height
                    
                    scrollView.reconfigureImageSize()
                    
                    let scale = min(scaledX, scaledY)
                    scrollView.transform = originalTransform.translatedBy(x: x, y: y).scaledBy(x: scale, y: scale)
                }
                
                let completion = {
                    scrollView.transform = originalTransform
                    scrollView.frame = self.view.bounds
                    scrollView.reconfigureImageSize()
                    
                    continuation.resume()
                }
                
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                    animation()
                } completion: { _ in
                    completion()
                }
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
                view.preferredImageDynamicRange = .high
            } else {
                LibLogger.libDefault.log("provideContentView")
            }
        }
        return view
    }
    
    func onDoubleTap(imageScrollView: UIImageScrollView) -> Bool {
        return false
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        DispatchQueue.main.async {
            self.onZoomChanged?(scrollView.minimumZoomScale...scrollView.maximumZoomScale, scrollView.zoomScale)
        }
    }
    
    // MARK: PHLivePhotoViewDelegate
    func livePhotoView(_ livePhotoView: PHLivePhotoView, canBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) -> Bool {
        LibLogger.libDefault.log("livePhotoView canBeginPlaybackWith")
        return true
    }
    
    func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
        LibLogger.libDefault.log("livePhotoView willBeginPlaybackWith")
    }
    
    func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
        LibLogger.libDefault.log("livePhotoView didEndPlaybackWith")
        hideLivePhotoView()
    }
}
#endif
