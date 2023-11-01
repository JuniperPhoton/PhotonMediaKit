//
//  UIImageViewerTitleBar.swift
//  MyerTidy (iOS)
//
//  Created by Photon Juniper on 2023/1/6.
//

import SwiftUI
import PhotonUtility
import PhotonMediaKit
import Photos

public protocol UIImageViewerEditSourceProvider: AnyObject {
    func requestDelete(phAsset: PHAsset)
}

/// Provide title bar implementation to ``UIImageViewer``.
public protocol UIImageViewerOrnamentProvider {
    associatedtype TitleBarContentView: View
    associatedtype ToolBarContentView: View
    associatedtype AssetProvider: MediaAssetProvider
    
    func onSetup(editSourceProvider: any UIImageViewerEditSourceProvider)
    
    /// Provide the SwiftUI View for title bar. After invoking this method, the view will
    /// be added to the view hierarchy.
    @ViewBuilder
    func provideTitleBarView() -> TitleBarContentView
    
    /// Provide the SwiftUI View for tool bar. After invoking this method, the view will
    /// be added to the view hierarchy.
    @ViewBuilder
    func provideToolBarView() -> ToolBarContentView
    
    /// When this title bar should be updated, this method will be invoked
    /// with the current ``MediaAssetProvider``.
    func onUpdateTitleBar(provider: AssetProvider)
    
    /// When this tool bar should be updated, this method will be invoked
    /// with the current ``MediaAssetProvider``.
    func onUpdateToolBar(provider: AssetProvider)
}
