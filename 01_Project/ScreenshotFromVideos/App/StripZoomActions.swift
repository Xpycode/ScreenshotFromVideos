//
//  StripZoomActions.swift
//  ScreenshotFromVideos
//
//  FocusedValue plumbing for the View > Zoom menu commands.
//  LeftPaneView publishes a StripZoomActions whenever a StripModel exists;
//  ZoomCommands reads it via @FocusedValue so the menu items only fire
//  (and only enable) while a video is loaded.
//

import SwiftUI

struct StripZoomActions {
    let zoomIn: @MainActor () -> Void
    let zoomOut: @MainActor () -> Void
    let resetZoom: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var stripZoom: StripZoomActions?
}

struct ZoomCommands: Commands {
    @FocusedValue(\.stripZoom) private var zoom

    var body: some Commands {
        // Merge into the standard "View" menu rather than CommandMenu("View"),
        // which would create a *second* View menu beside the system one.
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Zoom In") { zoom?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(zoom == nil)

            Button("Zoom Out") { zoom?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom == nil)

            Button("Reset Zoom") { zoom?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom == nil)
        }
    }
}
