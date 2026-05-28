//
//  FilePickers.swift
//  ScreenshotFromVideos
//
//  NSOpenPanel helpers. Distilled from CropBatch/Views/ActionButtonsView.swift
//  and VideoWallpaper/UI/SourceFoldersView.swift.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePickers {
    /// Modal panel for picking one or more video files.
    static func pickVideos() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Videos"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// Modal panel for picking an output folder.
    static func pickOutputFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
