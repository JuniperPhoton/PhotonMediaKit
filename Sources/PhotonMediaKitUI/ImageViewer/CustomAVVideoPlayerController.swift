//
//  CustomAVVideoPlayerController.swift
//  MyerTidy (iOS)
//
//  Created by Photon Juniper on 2023/10/15.
//

import Foundation
import AVKit

#if canImport(UIKit)
class CustomAVVideoPlayerController: AVPlayerViewController {
    private var avPlayer: AVPlayer? = nil
    
    func setupPlayer(avAsset: AVAsset) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        
        let item = AVPlayerItem(asset: avAsset)
        avPlayer = AVPlayer(playerItem: item)
        
        self.player = avPlayer
    }
    
    func play() {
        self.avPlayer?.play()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
}
#endif
