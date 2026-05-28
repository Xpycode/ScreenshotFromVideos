//
//  ScreenshotFromVideosApp.swift
//  ScreenshotFromVideos
//
//  App-shell modifiers per cookbook 00-app-shell.md (MANDATORY): hidden
//  title bar + dark color scheme. `.environment(\.theme, .dark)` is
//  intentionally skipped — Theme is a static enum, not an EnvironmentKey,
//  and views already read `Theme.primaryBackground` etc. directly.
//

import SwiftUI

@main
struct ScreenshotFromVideosApp: App {
    // VM lives at the App level so the Commands block and ContentView share
    // the same instance. Single-window app — no multi-window concerns.
    @State private var vm = ExtractionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 620)
        .commands {
            // Replace the default (non-functional) "New" item with Open
            // Video. Output-folder picking is exposed via the right-pane
            // button only — adding a menu item for it would be redundant
            // since users set the output folder once per session.
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") {
                    if let url = FilePickers.pickVideos().first {
                        Task { await vm.load(url) }
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            ZoomCommands()
        }
    }
}
