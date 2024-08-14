//
//  File.swift
//  
//
//  Created by Photon Juniper on 2023/10/31.
//

import Foundation
import SwiftUI
import PhotonMediaKit

/// A view to display a ``MediaAssetRes`` thumbnail image, which can be used in a list or a grid view.
public struct PHAssetImageView: View {
    let asset: MediaAssetRes
    let contentMode: ContentMode
    
    @State private var cgImage: CGImage? = nil
    
    public init(asset: MediaAssetRes, contentMode: ContentMode = .fill) {
        self.asset = asset
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
        }.task {
            await loadImage()
        }.onDisappear {
            release()
        }
    }
    
    private func loadImage() async {
        self.cgImage = await MediaAssetLoader().fetchThumbnailCGImage(phAsset: asset.phAsset)
    }
    
    private func release() {
        self.cgImage = nil
    }
}
