//
//  ContentView.swift
//  ScreenshotFromVideos
//
//  HSplitView shell wiring the left (player + capture) and right
//  (settings + export) panes to a single ExtractionViewModel. The drop
//  target lives here so a video file dropped anywhere in the window
//  routes to `vm.load`, and a folder drop routes to `vm.setOutputFolder`.
//

import SwiftUI

struct ContentView: View {
    let vm: ExtractionViewModel

    var body: some View {
        HSplitView {
            LeftPaneView(vm: vm)
            RightPaneView(vm: vm)
        }
        .autosaveSplitView(named: "MainSplit")
        .frame(minWidth: 720, minHeight: 480)
        .toolbarRole(.editor)
        .videoDropTarget(
            onFolder: { url in vm.setOutputFolder(url) },
            onVideos: { urls in
                if let first = urls.first {
                    Task { await vm.load(first) }
                }
            }
        )
    }
}

#Preview {
    ContentView(vm: ExtractionViewModel())
}
