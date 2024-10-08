//
//  ImageViewerUIKit.swift
//  MyerTidy (iOS)
//
//  Created by Photon Juniper on 2023/1/5.
//

import Foundation
import Photos
import SwiftUI
import PhotonMediaKit
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

/// An object to sync information between cell view and ``UIImageViewer``.
@MainActor
public class CellLocationSyncer: ObservableObject {
    private static let invalidatedValue: Int = -1
    
    /// Current index of the ``UIImageViewer``. This value should be set within ``UIImageViewer``
    public private(set) var currentIndex: Int = CellLocationSyncer.invalidatedValue
    public private(set) var previousIndex: Int = CellLocationSyncer.invalidatedValue
    
    /// Current frame of the cell view in image list. This value should be set within the list.
    public var currentFrame: CGRect = .zero
    
    public init() {
        // empty
    }
    
    /// Update the current index and notify changes.
    public func updateCurrentIndex(_ index: Int) {
        self.previousIndex = currentIndex
        self.currentIndex = index
        self.objectWillChange.send()
    }
    
    /// Invalidate the indexes. Unlike ``updateCurrentIndex(_:)``, this method won't trigger any updates.
    public func invalidate() {
        self.previousIndex = CellLocationSyncer.invalidatedValue
        self.currentIndex = CellLocationSyncer.invalidatedValue
    }
}

#if canImport(UIKit)
public class UIImageViewer<
    AssetProvider: MediaAssetProvider,
    OrnamentProvider: UIImageViewerOrnamentProvider
>: UIPageViewController, UIImageViewerEditSourceProvider, UIGestureRecognizerDelegate, UIPageViewControllerDataSource, UIPageViewControllerDelegate where OrnamentProvider.AssetProvider == AssetProvider {
    var syncer: CellLocationSyncer = CellLocationSyncer()
    var onRequestDismiss: ((Bool) -> Void)? = nil
    var onRequestDismissRootController: (() -> Void)? = nil
    var animateTransitToStartLocation = false
    var animateDismissToStartLocation = false
    var animateBackgroundOnViewLoaded = true
    var prefersHighDynamicRange = false
    
    private(set) var images: [AssetProvider] = []
    
    var ornamentProvider: OrnamentProvider? = nil
    
    private var titleViewController: UIHostingController<OrnamentProvider.TitleBarContentView>? = nil
    private var toolBarViewController: UIHostingController<OrnamentProvider.ToolBarContentView>? = nil
    private var currentViewController: UIImageDetailViewController<AssetProvider>? = nil
    
    private lazy var gradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.black.withAlphaComponent(0.7).cgColor,
                           UIColor.clear.cgColor]
        return gradient
    }()
    
    private lazy var titleBarContainer: UIView = {
        return UIView()
    }()
    
    private lazy var toolBarContainer: UIView = {
        return UIView()
    }()
    
    private var showOrnamentUI = true
    private var recognizerDelegate = RecognizerDelegate()
    
    func setImages(_ images: [AssetProvider]) {
        self.images.removeAll()
        for image in images {
            self.images.append(image)
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.dataSource = self
        self.delegate = self
        
        self.view.backgroundColor = .clear
        
        let action = {
            self.view.backgroundColor = .black
        }
        if animateBackgroundOnViewLoaded {
            UIView.animate(withDuration: 0.3, animations: action)
        } else {
            action()
        }
        
        setCurrentController(direction: .forward)
        
        if let scrollView = getScrollView() {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan))
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
        }
        
        self.view.addSubview(titleBarContainer)
        self.view.addSubview(toolBarContainer)
        
        let tapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(onSingleTap)
        )
        
        // We should use a dedicated delegate since UIPageViewController has its own implementation.
        tapRecognizer.delegate = recognizerDelegate
        self.view.addGestureRecognizer(tapRecognizer)
        
        // Disable autoresizing mask translation
        titleBarContainer.translatesAutoresizingMaskIntoConstraints = false
        toolBarContainer.translatesAutoresizingMaskIntoConstraints = false
        titleViewController?.view.translatesAutoresizingMaskIntoConstraints = false
        toolBarViewController?.view.translatesAutoresizingMaskIntoConstraints = false
        gradientLayer.superlayer?.sublayers?.first?.masksToBounds = false
        
        // Define constraints for titleBarContainer
        NSLayoutConstraint.activate([
            titleBarContainer.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            titleBarContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            titleBarContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            titleBarContainer.heightAnchor.constraint(equalToConstant: 80 + self.view.safeAreaInsets.top)
        ])
        
        // Define constraints for toolBarContainer
        NSLayoutConstraint.activate([
            toolBarContainer.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            toolBarContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            toolBarContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            toolBarContainer.heightAnchor.constraint(equalToConstant: 80 + self.view.safeAreaInsets.bottom)
        ])
        
        // Assuming gradientLayer is a CAGradientLayer added to self.view.layer
        gradientLayer.frame = self.view.bounds
        
        if let titleView = titleViewController?.view {
            NSLayoutConstraint.activate([
                titleView.topAnchor.constraint(equalTo: titleBarContainer.bottomAnchor),
                titleView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                titleView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                titleView.bottomAnchor.constraint(equalTo: toolBarContainer.topAnchor)
            ])
        }
        
        if let toolBarView = toolBarViewController?.view {
            NSLayoutConstraint.activate([
                toolBarView.topAnchor.constraint(equalTo: titleBarContainer.bottomAnchor),
                toolBarView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                toolBarView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                toolBarView.bottomAnchor.constraint(equalTo: toolBarContainer.topAnchor)
            ])
        }
        
        if let scrollView = getScrollView() {
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: titleBarContainer.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: toolBarContainer.topAnchor)
            ])
        }
        
        if let ornamentProvider = ornamentProvider {
            let titleViewController = UIHostingController(rootView: ornamentProvider.provideTitleBarView())
            titleViewController.view.backgroundColor = UIColor.clear
            
            self.titleViewController = titleViewController
            titleBarContainer.addSubview(titleViewController.view)
            
            titleViewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                titleViewController.view.topAnchor.constraint(equalTo: self.titleBarContainer.topAnchor),
                titleViewController.view.leadingAnchor.constraint(equalTo: self.titleBarContainer.leadingAnchor),
                titleViewController.view.trailingAnchor.constraint(equalTo: self.titleBarContainer.trailingAnchor),
                titleViewController.view.bottomAnchor.constraint(equalTo: self.titleBarContainer.bottomAnchor)
            ])
            
            let toolBarViewController = UIHostingController(rootView: ornamentProvider.provideToolBarView())
            toolBarViewController.view.backgroundColor = UIColor.clear
            
            self.toolBarViewController = toolBarViewController
            toolBarContainer.addSubview(toolBarViewController.view)
            
            toolBarViewController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                toolBarViewController.view.topAnchor.constraint(equalTo: self.toolBarContainer.topAnchor),
                toolBarViewController.view.leadingAnchor.constraint(equalTo: self.toolBarContainer.leadingAnchor),
                toolBarViewController.view.trailingAnchor.constraint(equalTo: self.toolBarContainer.trailingAnchor),
                toolBarViewController.view.bottomAnchor.constraint(equalTo: self.toolBarContainer.bottomAnchor)
            ])
            
            titleBarContainer.alpha = 0
            toolBarContainer.alpha = 0
            
            UIView.animate(withDuration: 0.3) {
                self.titleBarContainer.alpha = 1
                self.toolBarContainer.alpha = 1
            }
        }
    }
    
    private func setCurrentController(direction: NavigationDirection) {
        guard let firstImage = images[safeIndex: syncer.currentIndex] else {
            return
        }
        
        let controller = createDetailController(for: firstImage)
        if self.currentViewController == nil && animateTransitToStartLocation {
            controller.startFrame = syncer.currentFrame
        }
        
        currentViewController = controller
        setViewControllers([controller], direction: direction, animated: true)
        updateOrnamentUI()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        let parent = self.parent
        parent?.view.backgroundColor = UIColor.clear
    }
    
    // MARK: UIGestureRecognizerDelegate
    public func gestureRecognizerShouldBegin(_ current: UIGestureRecognizer) -> Bool {
        guard let currentPan = current as? UIPanGestureRecognizer else {
            return false
        }
        
        let velocity = currentPan.velocity(in: currentPan.view)
        return velocity.y >= 160
    }
    
    private func toggleOrnamentVisibility(hide: Bool) {
        let targetAlpha = hide ? 0.0 : 1.0
        
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseIn) {
            self.titleBarContainer.alpha = targetAlpha
            self.toolBarContainer.alpha = targetAlpha
        }
    }
    
    @objc
    private func onPan(gesture: UIPanGestureRecognizer) {
        guard let targetView = gesture.view else {
            return
        }
        
        guard let currentViewController = currentViewController else {
            return
        }
        
        let translation = gesture.translation(in: targetView)
        let velocity = gesture.velocity(in: targetView)
        
        if gesture.state == .ended {
            if translation.y >= 300 || velocity.y >= 400 {
                if self.animateDismissToStartLocation {
                    if !animateToDismissToStartFrame(targetView: targetView,
                                                     currentViewController: currentViewController) {
                        animateToDismiss(targetView: targetView)
                    }
                } else {
                    animateToDismiss(targetView: targetView)
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    targetView.transform = CGAffineTransform.identity
                    self.view.backgroundColor = UIColor.black
                }
            }
            return
        }
        
        if translation.y > 0 {
            targetView.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
            let progress = translation.y / self.view.frame.height
            self.view.backgroundColor = self.view.backgroundColor?.withAlphaComponent((1 - progress).clamp(to: 0...1))
        }
    }
    
    // MARK: UIImageViewerEditSourceProvider
    public func requestDismiss() {
        guard let currentViewController = currentViewController else {
            return
        }
        guard let scrollView = getScrollView() else {
            return
        }
        
        currentViewController.resetZoomScale()
        
        if !animateToDismissToStartFrame(targetView: scrollView, currentViewController: currentViewController) {
            animateToDismiss(targetView: scrollView)
        }
    }
    
    public func requestDismissRootController() {
        onRequestDismissRootController?()
    }
    
    public func requestStartLivePhotoPlayback(playbackStyle: PHLivePhotoViewPlaybackStyle) {
        guard let currentViewController = currentViewController else {
            return
        }
        currentViewController.tryShowLivePhotoView(playbackStyle: playbackStyle)
    }
    
    public func requestDelete(phAsset: PHAsset) {
        Task { @MainActor in
            if await MediaAssetWriter.shared.delete(asset: phAsset) {
                let index = self.images.firstIndex { provider in
                    provider.phAssetRes.phAsset.localIdentifier == phAsset.localIdentifier
                }
                if let index = index {
                    var currentIndex = syncer.currentIndex
                    self.images.remove(at: index)
                    
                    let lower = 0
                    let upper = self.images.count - 1
                    if lower > upper {
                        self.requestDismiss(animated: false)
                        return
                    }
                    
                    currentIndex = currentIndex.clamp(to: lower...upper)
                    syncer.updateCurrentIndex(currentIndex)
                    setCurrentController(direction: currentIndex >= index ? .forward : .reverse)
                }
            }
        }
    }
    
    public func requestToggleFavorited(phAsset: PHAsset) {
        Task { @MainActor in
            if await requestToggleFavoritedInternal(phAsset: phAsset) {
                await updateCurrentAsset()
                updateOrnamentUI()
            }
        }
    }
    
    private func requestToggleFavoritedInternal(phAsset: PHAsset) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: phAsset)
                request.isFavorite = !phAsset.isFavorite
            }, completionHandler: { success, error in
                continuation.resume(returning: success)
            })
        }
    }
    
    private func animateToDismiss(targetView: UIView) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            targetView.transform = CGAffineTransform(translationX: 0, y: self.view.frame.height)
            self.view.alpha = 0.0
        } completion: { _ in
            self.requestDismiss(animated: false)
        }
    }
    
    private func animateToDismissToStartFrame(targetView: UIView,
                                              currentViewController: UIImageDetailViewController<AssetProvider>) -> Bool {
        let currentCellFrame = syncer.currentFrame
        
        guard let currentImageFrame = currentViewController.getAspectRatioFitImageFrame() else {
            return false
        }
        
        let scaleX = currentCellFrame.width / currentImageFrame.width
        let scaleY = currentCellFrame.height / currentImageFrame.height
        let scale = max(scaleX, scaleY)
        
        let currentFrame = targetView.frame
        let currentCenterPoint = CGPoint(x: currentFrame.width / 2, y: currentFrame.height / 2)
        let offsetX = currentCellFrame.midX - currentCenterPoint.x
        let offsetY = currentCellFrame.midY - currentCenterPoint.y
        
        // Since CALayer is added to the UIView, we want the frame to be relative to the bounds of targetView, not the frame.
        let originalMaskFrame = targetView.bounds
        
        let targetMaskForImage = AVMakeRect(aspectRatio: CGSize(width: 1, height: 1),
                                            insideRect: currentImageFrame)
        
        let targetMaskFrame = targetMaskForImage.offsetBy(dx: originalMaskFrame.origin.x,
                                                          dy: originalMaskFrame.origin.y)
        
        let maskLayer = CALayer()
        maskLayer.frame = originalMaskFrame
        maskLayer.backgroundColor = UIColor.white.cgColor
        targetView.layer.mask = maskLayer
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            targetView.transform = CGAffineTransform(translationX: offsetX, y: offsetY)
                .scaledBy(x: scale, y: scale)
            targetView.layer.mask?.frame = targetMaskFrame
            self.view.backgroundColor = .clear
            self.titleBarContainer.alpha = 0.0
            self.toolBarContainer.alpha = 0.0
        } completion: { _ in
            self.requestDismiss(animated: false)
        }
        
        return true
    }
    
    // Get the ScrollView of this UIPageViewController
    private func getScrollView() -> UIScrollView? {
        return self.view.subviews.first { v in
            v is UIScrollView
        } as? UIScrollView
    }
    
    private func createDetailController(for image: AssetProvider) -> UIImageDetailViewController<AssetProvider> {
        let controller = UIImageDetailViewController<AssetProvider>()
        controller.setImage(image)
        controller.setPrefersHighDynamicRange(prefersHighDynamicRange)
        controller.onRequestDismiss = { [weak self] in
            guard let self = self else { return }
            self.requestDismiss(animated: true)
        }
        controller.onZoomChanged = { [weak self] range, zoomFactor in
            guard let self = self else { return }
            let hide = (zoomFactor - range.lowerBound) > 0.0001
            if hide {
                self.toggleOrnamentVisibility(hide: hide)
            } else if showOrnamentUI {
                self.toggleOrnamentVisibility(hide: false)
            }
        }
        return controller
    }
    
    @objc private func onSingleTap(recognizer: UITapGestureRecognizer) {
        showOrnamentUI = self.titleBarContainer.alpha == 0.0
        self.toggleOrnamentVisibility(hide: !showOrnamentUI)
    }
    
    private func updateCurrentAsset() async {
        guard let current = currentViewController else {
            return
        }
        await current.asset?.updateCurrentAsset()
    }
    
    private func updateOrnamentUI() {
        guard let current = currentViewController else {
            return
        }
        if let provider = current.asset {
            ornamentProvider?.onSetup(editSourceProvider: self)
            ornamentProvider?.onUpdateTitleBar(provider: provider)
            ornamentProvider?.onUpdateToolBar(provider: provider)
        }
    }
    
    private func requestDismiss(animated: Bool) {
        if let onRequestDismiss = self.onRequestDismiss {
            onRequestDismiss(animated)
        } else {
            self.parent?.dismiss(animated: animated)
        }
    }
    
    // MARK: UIPageViewControllerDelegate
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let next = pendingViewControllers.first as? UIImageDetailViewController<AssetProvider> else {
            currentViewController = nil
            return
        }
        currentViewController = next
        currentViewController?.setAnimating(true)
        if let nextAsset = next.asset,
           let nextIndex = images.firstIndex(of: nextAsset) {
            syncer.updateCurrentIndex(nextIndex)
        }
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   didFinishAnimating finished: Bool,
                                   previousViewControllers: [UIViewController],
                                   transitionCompleted completed: Bool) {
        guard let previous = previousViewControllers.first as? UIImageDetailViewController<AssetProvider> else {
            return
        }
        previous.resetZoomScale()
        updateOrnamentUI()
        currentViewController?.setAnimating(false)
    }
    
    // MARK: UIPageViewControllerDataSource
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   viewControllerBefore viewController: UIViewController) -> UIViewController? {
        let index = currentOfIndex(viewController: viewController)
        
        if index <= 0 {
            return nil
        }
        let prevIndex = index - 1
        let prevImage = images[prevIndex]
        let controller = createDetailController(for: prevImage)
        return controller
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   viewControllerAfter viewController: UIViewController) -> UIViewController? {
        let index = currentOfIndex(viewController: viewController)
        
        if index < 0 || index >= images.count - 1 {
            return nil
        }
        let nextIndex = index + 1
        let nextImage = images[nextIndex]
        let controller = createDetailController(for: nextImage)
        return controller
    }
    
    public func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return images.count
    }
    
    func currentOfIndex(viewController: UIViewController) -> Int {
        guard let vc = viewController as? UIImageDetailViewController<AssetProvider> else {
            return -1
        }
        
        if let image = vc.asset {
            return images.firstIndex(of: image) ?? -1
        }
        
        return -1
    }
    
    var isPagingEnabled: Bool {
        get {
            return getScrollView()?.isScrollEnabled == true
        }
        set {
            getScrollView()?.isScrollEnabled = newValue
        }
    }
}

private class RecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let singleTap = gestureRecognizer as? UITapGestureRecognizer, singleTap.numberOfTapsRequired == 1 else {
            return false
        }
        
        guard let doubleTap = otherGestureRecognizer as? UITapGestureRecognizer, doubleTap.numberOfTapsRequired == 2 else {
            return false
        }
        
        return true
    }
}

private extension UIGestureRecognizer.State {
    func toString() -> String {
        switch self {
        case .began: return "began"
        case .ended: return "ended"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        case .changed: return "changed"
        case .possible: return "possible"
        case .recognized: return "recognized"
        default: return "default unknown"
        }
    }
}
#endif
