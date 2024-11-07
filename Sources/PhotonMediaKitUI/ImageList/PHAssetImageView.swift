//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/10/31.
//

import Foundation
import SwiftUI
import PhotonMediaKit

/// A view to display a ``CGImage`` thumbnail image, which can be used in a list or a grid view.
public struct PHAssetCGImageView: View {
    let cgImage: CGImage?
    let contentMode: ContentMode
    
    public init(cgImage: CGImage?, contentMode: ContentMode) {
        self.cgImage = cgImage
        self.contentMode = contentMode
    }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let cgImage = cgImage {
                    Image(cgImage, scale: 1.0, label: Text(""))
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .zIndex(1)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .matchParent()
                        .zIndex(0)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.animation(.default, value: cgImage)
    }
}

/// A view to display a ``MediaAssetRes`` thumbnail image, which can be used in a list or a grid view.
public struct PHAssetImageView: View {
    let asset: MediaAssetRes
    let contentMode: ContentMode
    let version: MediaAssetVersion
    let isNetworkAccessAllowed: Bool
    let fallbackToUseCurrentVersion: Bool
    
    @State private var cgImage: CGImage? = nil
    
    public init(
        asset: MediaAssetRes,
        contentMode: ContentMode = .fill,
        version: MediaAssetVersion = .current,
        isNetworkAccessAllowed: Bool = false,
        fallbackToUseCurrentVersion: Bool = true
    ) {
        self.asset = asset
        self.contentMode = contentMode
        self.version = version
        self.isNetworkAccessAllowed = isNetworkAccessAllowed
        self.fallbackToUseCurrentVersion = fallbackToUseCurrentVersion
    }
    
    public var body: some View {
        PHAssetCGImageView(cgImage: cgImage, contentMode: contentMode)
            .task {
                await loadImage()
            }.onDisappear {
                self.cgImage = nil
            }
    }
    
    private func loadImage() async {
        var image = await MediaAssetLoader().fetchThumbnailCGImage(
            phAsset: asset.phAsset,
            version: version,
            isNetworkAccessAllowed: isNetworkAccessAllowed
        )
        
        if image == nil && version == .original {
            image = await MediaAssetLoader().fetchThumbnailCGImage(
                phAsset: asset.phAsset,
                version: .current,
                isNetworkAccessAllowed: isNetworkAccessAllowed
            )
        }
        
        self.cgImage = image
    }
    
    private func release() {
        self.cgImage = nil
    }
}
