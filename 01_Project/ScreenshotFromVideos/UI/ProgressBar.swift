//
//  ProgressBar.swift
//  ScreenshotFromVideos
//
//  Lifted from VideoWallpaper/UI/NowPlayingView.swift (the standalone struct).
//

import SwiftUI

struct ProgressBar: View {
    let value: Double
    let total: Double

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
    }
}
