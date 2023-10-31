//
//  UIImageViewerTitleBar.swift
//  MyerTidy (iOS)
//
//  Created by Photon Juniper on 2023/1/6.
//

import SwiftUI
import PhotonUtility
import PhotonMediaKit

/// Provide title bar implementation to ``UIImageViewer``.
public protocol UIImageViewerTitleBarProvider {
    associatedtype ContentView: View
    associatedtype AssetProvider: MediaAssetProvider
    
    /// Provide the SwiftUI View. After invoking this method, the view will
    /// be added to the view hierarchy.
    func provideView() -> ContentView
    
    /// When this title bar should be updated, this method will be invoked
    /// with the current ``MediaAssetProvider``.
    func onUpdate(provider: AssetProvider)
}
