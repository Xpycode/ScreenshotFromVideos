//
//  SplitViewAutosave.swift
//  ScreenshotFromVideos
//
//  Lifted from cookbook 01-window-layouts.md "Autosave Divider Positions"
//  (originally Penumbra/Utils/View+SplitViewAutosave.swift). Walks up the
//  AppKit view hierarchy to find the underlying NSSplitView and sets its
//  `autosaveName` so divider position persists across launches.
//

import SwiftUI
import AppKit

private struct SplitViewAutosaveHelper: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            var parent = view.superview
            while parent != nil {
                if let splitView = parent as? NSSplitView {
                    splitView.autosaveName = autosaveName
                    return
                }
                parent = parent?.superview
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Enables divider position autosaving for `HSplitView` / `VSplitView`.
    /// Apply on the split-view itself, not on a child.
    func autosaveSplitView(named name: String) -> some View {
        self.background(SplitViewAutosaveHelper(autosaveName: name))
    }
}
