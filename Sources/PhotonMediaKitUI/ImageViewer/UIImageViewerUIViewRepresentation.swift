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
                                                TitleBarProvider: UIImageViewerTitleBarProvider>: UIViewControllerRepresentable where TitleBarProvider.AssetProvider == AssetProvider {
    public typealias UIViewControllerType = UIImageViewer<AssetProvider, TitleBarProvider>
    
    private let images: [AssetProvider]
    private let syncer: CellLocationSyncer
    private let titleBarProvider: TitleBarProvider
    private let animatedDismissToStartLocation: Bool
    private let onRequestDismiss: ((Bool) -> Void)
    
    public init(
        images: [AssetProvider],
        syncer: CellLocationSyncer,
        titleBarProvider: TitleBarProvider,
        animatedDismissToStartLocation: Bool,
        onRequestDismiss: @escaping ((Bool) -> Void)
    ) {
        self.images = images
        self.syncer = syncer
        self.titleBarProvider = titleBarProvider
        self.animatedDismissToStartLocation = animatedDismissToStartLocation
        self.onRequestDismiss = onRequestDismiss
    }
    
    public func updateUIViewController(
        _ uiViewController: UIImageViewer<AssetProvider, TitleBarProvider>,
        context: Context
    ) {
        // ignored
    }
    
    public func makeUIViewController(context: Context) -> UIImageViewer<AssetProvider, TitleBarProvider> {
        let controller = UIImageViewer<AssetProvider, TitleBarProvider>(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        controller.setImages(self.images)
        controller.onRequestDismiss = onRequestDismiss
        controller.titleBarProvider = titleBarProvider
        controller.syncer = self.syncer
        controller.animatedDismissToStartLocation = self.animatedDismissToStartLocation
        return controller
    }
}
#endif
