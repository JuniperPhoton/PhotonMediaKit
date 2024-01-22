//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/10/30.
//

import Foundation
import Foundation
import SwiftUI
import PhotonUtilityView
import PhotonMediaKit

#if canImport(UIKit)
@available(iOS 15.0, *)
public struct UIImageViewerUIViewRepresentation<AssetProvider: MediaAssetProvider,
                                                OrnamentProvider: UIImageViewerOrnamentProvider>: UIViewControllerRepresentable where OrnamentProvider.AssetProvider == AssetProvider {
    public typealias UIViewControllerType = UIImageViewer<AssetProvider, OrnamentProvider>
    
    private let images: [AssetProvider]
    private let syncer: CellLocationSyncer
    private let ornamentProvider: OrnamentProvider
    private let animateDismissToStartLocation: Bool
    private let animateBackgroundOnViewLoaded: Bool
    private let onRequestDismiss: ((Bool) -> Void)
    
    public init(
        images: [AssetProvider],
        syncer: CellLocationSyncer,
        ornamentProvider: OrnamentProvider,
        animateDismissToStartLocation: Bool,
        animateBackgroundOnViewLoaded: Bool,
        onRequestDismiss: @escaping ((Bool) -> Void)
    ) {
        self.images = images
        self.syncer = syncer
        self.ornamentProvider = ornamentProvider
        self.animateDismissToStartLocation = animateDismissToStartLocation
        self.animateBackgroundOnViewLoaded = animateBackgroundOnViewLoaded
        self.onRequestDismiss = onRequestDismiss
    }
    
    public func updateUIViewController(
        _ uiViewController: UIImageViewer<AssetProvider, OrnamentProvider>,
        context: Context
    ) {
        // ignored
    }
    
    public func makeUIViewController(context: Context) -> UIImageViewer<AssetProvider, OrnamentProvider> {
        let controller = UIImageViewer<AssetProvider, OrnamentProvider>(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        controller.setImages(self.images)
        controller.onRequestDismiss = onRequestDismiss
        controller.ornamentProvider = ornamentProvider
        controller.syncer = self.syncer
        controller.animateDismissToStartLocation = self.animateDismissToStartLocation
        controller.animateBackgroundOnViewLoaded = self.animateBackgroundOnViewLoaded
        return controller
    }
}
#endif
