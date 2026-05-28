//
//  DropHandling.swift
//  ScreenshotFromVideos
//
//  Drop target accepting folders and video files from Finder. Both
//  callbacks run on the main actor.
//
//  Strict-concurrency note: NSItemProvider is non-Sendable, so the load
//  callbacks must stay on a bg queue (no Task / TaskGroup capturing them).
//  Each completion hops back to the main actor via `Task { @MainActor in }`
//  where a small @MainActor collector aggregates results and invokes the
//  caller's callbacks once everything has resolved.
//

import SwiftUI
import UniformTypeIdentifiers

private struct VideoDropModifier: ViewModifier {

    let onFolder: @MainActor (URL) -> Void
    let onVideos: @MainActor ([URL]) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.04))
                        )
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let relevant = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !relevant.isEmpty else { return false }

        let total = relevant.count
        let collector = DropCollector(
            total: total,
            onFolder: onFolder,
            onVideos: onVideos
        )

        for provider in relevant {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let raw = item as? URL {
                    url = raw
                } else {
                    url = nil
                }

                Task { @MainActor in
                    collector.record(url: url)
                }
            }
        }

        return true
    }
}

@MainActor
private final class DropCollector {
    private let total: Int
    private var received = 0
    private var videos: [URL] = []
    private let onFolder: (URL) -> Void
    private let onVideos: ([URL]) -> Void

    init(
        total: Int,
        onFolder: @escaping @MainActor (URL) -> Void,
        onVideos: @escaping @MainActor ([URL]) -> Void
    ) {
        self.total = total
        self.onFolder = onFolder
        self.onVideos = onVideos
    }

    func record(url: URL?) {
        received += 1

        if let url {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentTypeKey]
            if let values = try? url.resourceValues(forKeys: keys) {
                if values.isDirectory == true {
                    onFolder(url)
                } else if values.contentType?.conforms(to: .movie) == true {
                    videos.append(url)
                }
            }
        }

        if received == total, !videos.isEmpty {
            onVideos(videos)
        }
    }
}

extension View {
    /// Drop target accepting folders and video files from Finder.
    /// Both callbacks run on the main actor.
    func videoDropTarget(
        onFolder: @MainActor @escaping (URL) -> Void,
        onVideos: @MainActor @escaping ([URL]) -> Void
    ) -> some View {
        modifier(VideoDropModifier(onFolder: onFolder, onVideos: onVideos))
    }
}
