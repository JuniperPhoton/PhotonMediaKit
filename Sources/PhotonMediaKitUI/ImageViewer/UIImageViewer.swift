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
import PinLayout

#if canImport(UIKit)
import UIKit

/// An object to sync information between cell view and ``UIImageViewer``.
@MainActor
public class CellLocationSyncer: ObservableObject {
    /// Current index of the ``UIImageViewer``. This value should be set within ``UIImageViewer``
    @Published public var currentIndex: Int = 0
    
    /// Current frame of the cell view in image list. This value should be set within the list.
    public var currentFrame: CGRect = .zero
    
    public init() {
        // empty
    }
}

public class UIImageViewer<
    AssetProvider: MediaAssetProvider,
    OrnamentProvider: UIImageViewerOrnamentProvider
>: UIPageViewController, UIImageViewerEditSourceProvider, UIGestureRecognizerDelegate, UIPageViewControllerDataSource, UIPageViewControllerDelegate where OrnamentProvider.AssetProvider == AssetProvider {
    var syncer: CellLocationSyncer = CellLocationSyncer()
    var onRequestDismiss: ((Bool) -> Void)? = nil
    var animatedDismissToStartLocation = false
    
    private(set) var images: [AssetProvider] = []
    
    var ornamentProvider: OrnamentProvider? = nil
    
    private var titleView: UIHostingController<OrnamentProvider.TitleBarContentView>? = nil
    private var toolBarView: UIHostingController<OrnamentProvider.ToolBarContentView>? = nil
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
        UIView.animate(withDuration: 0.3) {
            self.view.backgroundColor = .black
        }
        
        setCurrentController()
        updateOrnamentUI()

        if let scrollView = getScrollView() {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan))
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
        }
        
        self.view.addSubview(titleBarContainer)
        self.view.addSubview(toolBarContainer)
        
        if let ornamentProvider = ornamentProvider {
            let titleView = UIHostingController(rootView: ornamentProvider.provideTitleBarView())
            titleView.view.backgroundColor = UIColor.clear
            
            self.titleView = titleView
            titleBarContainer.addSubview(titleView.view)
            
            let toolBarView = UIHostingController(rootView: ornamentProvider.provideToolBarView())
            toolBarView.view.backgroundColor = UIColor.clear
            
            self.toolBarView = toolBarView
            toolBarContainer.addSubview(toolBarView.view)
            
            titleBarContainer.alpha = 0
            toolBarContainer.alpha = 0
            
            UIView.animate(withDuration: 0.3) {
                self.titleBarContainer.alpha = 1
                self.toolBarContainer.alpha = 1
            }
        }
    }
    
    private func setCurrentController() {
        guard let firstImage = images[safeIndex: syncer.currentIndex] else {
            return
        }
        
        let controller = createDetailController(for: firstImage)
        if self.currentViewController == nil {
            controller.startFrame = syncer.currentFrame
        }
        
        currentViewController = controller
        setViewControllers([controller], direction: .forward, animated: true)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        let parent = self.parent
        parent?.view.backgroundColor = UIColor.clear
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        titleBarContainer.pin
            .top()
            .start()
            .end()
            .height(80 + self.view.safeAreaInsets.top)
        
        toolBarContainer.pin
            .bottom()
            .start()
            .end()
            .height(80 + self.view.safeAreaInsets.bottom)
        
        gradientLayer.pin.all()
        titleView?.view.pin.all()
        toolBarView?.view.pin.all()
        
        if let scrollView = getScrollView() {
            // Transform not work with auto-layout, we use pin layout insteads
            scrollView.pin.all()
        }
    }
    
    public func gestureRecognizerShouldBegin(_ current: UIGestureRecognizer) -> Bool {
        guard let currentPan = current as? UIPanGestureRecognizer else {
            return false
        }
        
        let velocity = currentPan.velocity(in: currentPan.view)
        return velocity.y >= 160
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
                if self.animatedDismissToStartLocation {
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
    
    public func requestDelete(phAsset: PHAsset) {
        Task {
            if await MediaAssetWriter.shared.delete(asset: phAsset) {
                let index = self.images.firstIndex { provider in
                    provider.phAssetRes.phAsset.localIdentifier == phAsset.localIdentifier
                }
                if let index = index {
                    var currentIndex = syncer.currentIndex
                    self.images.remove(at: index)
                    
                    currentIndex = currentIndex.clamp(to: 0...self.images.count - 1)
                    syncer.currentIndex = currentIndex
                    setCurrentController()
                }
            }
        }
    }
    
    private func animateToDismiss(targetView: UIView) {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
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
    
    private func getScrollView() -> UIScrollView? {
        return self.view.subviews.first { v in
            v is UIScrollView
        } as? UIScrollView
    }
    
    private func createDetailController(for image: AssetProvider) -> UIImageDetailViewController<AssetProvider> {
        let controller = UIImageDetailViewController<AssetProvider>()
        controller.setImage(image)
        controller.onRequestDismiss = { [weak self] in
            guard let self = self else { return }
            self.requestDismiss(animated: true)
        }
        return controller
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
        if let nextAsset = next.asset,
           let nextIndex = images.firstIndex(of: nextAsset) {
            syncer.currentIndex = nextIndex
        }
        next.loadImageProgressively()
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController,
                                   didFinishAnimating finished: Bool,
                                   previousViewControllers: [UIViewController],
                                   transitionCompleted completed: Bool) {
        guard let previous = previousViewControllers.first as? UIImageDetailViewController<AssetProvider> else {
            return
        }
        previous.reset()
        updateOrnamentUI()
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
