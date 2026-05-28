//
//  PlayerView.swift
//  ScreenshotFromVideos
//
//  AppKit AVPlayerView wrapped for SwiftUI. Per Apple SDK research, macOS
//  doesn't expose `currentTime` from `VideoPlayer`, so we use AVPlayerView
//  to keep QuickTime-style chrome (play/pause/scrub/frame-step) and let
//  the view-model read `player.currentTime()` directly.
//
//  Do NOT apply `.clipShape` to this view — there's a known AVPlayerView
//  hit-test bug when its layer is clipped (controls become unresponsive).
//

import SwiftUI
import AVKit

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFrameSteppingButtons = true
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
