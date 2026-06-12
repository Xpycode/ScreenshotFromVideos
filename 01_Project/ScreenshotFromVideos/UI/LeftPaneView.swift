//
//  LeftPaneView.swift
//  ScreenshotFromVideos
//
//  Left side of the HSplitView shell. Two states:
//   - Empty:   drop hint + "Pick video…" button (NSOpenPanel).
//   - Loaded:  PlayerView fills the pane; below it a footer row with the
//              live current-time label, a Copy-frame button (⌘C → clipboard),
//              the Capture-this-frame button (Q → export queue), and a
//              captured-count label.
//
//  The video drop modifier lives at the ContentView level, not here, so
//  this view is purely a presenter of the view-model.
//
//  Live time is read from `vm.player.currentTime()` on each TimelineView
//  tick — no `addPeriodicTimeObserver` token to manage, no leak risk.
//

import SwiftUI
import CoreMedia
import AVFoundation

struct LeftPaneView: View {
    @Bindable var vm: ExtractionViewModel
    @State private var stripModel: StripModel?
    @GestureState private var liveScale: Double = 1.0

    var body: some View {
        Group {
            if vm.player == nil {
                emptyView
            } else {
                loadedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryBackground)
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 4) {
                Text("Drop a video here")
                    .font(.title3)
                    .foregroundStyle(Theme.primaryText)
                Text("or pick one below")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }

            Button("Pick video…") {
                if let url = FilePickers.pickVideos().first {
                    Task { await vm.load(url) }
                }
            }
            .buttonStyle(FCPButtonStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Loaded state

    @ViewBuilder
    private var loadedView: some View {
        VStack(spacing: 0) {
            VSplitView {
                PlayerView(player: vm.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 120)
                    .overlay { burnInPreviewOverlay }

                Group {
                    if let stripModel {
                        ThumbnailStripView(model: stripModel, player: vm.player, vm: vm)
                    } else {
                        Theme.secondaryBackground
                    }
                }
                .frame(minHeight: 100, idealHeight: 320, maxHeight: .infinity)
            }
            .autosaveSplitView(named: "LeftPaneVSplit")

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.secondaryBackground)
        }
        .task(id: vm.metadata) {
            rebuildStripModel()
        }
        .simultaneousGesture(pinch)
        .focusedSceneValue(\.stripZoom, stripModel.map { m in
            StripZoomActions(
                zoomIn: { m.zoomIn() },
                zoomOut: { m.zoomOut() },
                resetZoom: { m.resetZoom() }
            )
        })
    }

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .updating($liveScale) { value, state, _ in
                state = value.magnification
            }
            .onChanged { value in
                if let m = stripModel, !m.isMagnifying {
                    m.onMagnifyStart()
                }
                stripModel?.onZoomChange(magnification: value.magnification)
            }
            .onEnded { value in
                stripModel?.commitZoom(value.magnification)
                stripModel?.onMagnifyEnd()
            }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                vm.clear()
            } label: {
                Label("Unload", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Remove this video from the app. The source file is not deleted.")

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                Text(currentTimeString)
                    .font(.system(size: 13, weight: .thin).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }

            Spacer()

            Button {
                vm.copyCurrentFrameToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(FCPButtonStyle())
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy the current frame to the clipboard (⌘C)")

            Button("Capture this frame") {
                vm.captureCurrentFrame()
            }
            .buttonStyle(FCPButtonStyle())
            .help("Add the current frame to the export queue (press Q with the strip focused)")

            Text("\(vm.capturedCount) captured")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 80, alignment: .trailing)
        }
    }

    private var currentTimeString: String {
        guard let player = vm.player else { return "00:00.000" }
        return TimestampFormatter.string(from: player.currentTime())
    }

    // MARK: - Burn-in preview

    /// WYSIWYG-ish preview of the export timestamp overlay, pinned to the actual
    /// letterboxed video rect (not the pane) so corner + relative size match what
    /// `ImageExportService.applyTextOverlay` will burn in. Live time comes from
    /// the same TimelineView pattern the footer uses. Proxy only — the black
    /// stroke is approximated with a shadow halo.
    @ViewBuilder
    private var burnInPreviewOverlay: some View {
        if vm.overlay.enabled, let meta = vm.metadata, meta.width > 0, meta.height > 0 {
            GeometryReader { geo in
                let rect = fittedVideoRect(
                    in: geo.size,
                    aspect: CGFloat(meta.width) / CGFloat(meta.height)
                )
                let fontSize = rect.height * CGFloat(vm.overlay.fontPercent)
                let inset = fontSize * 0.4   // matches applyTextOverlay's padding
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                    Text(currentTimeString)
                        .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1)
                        .shadow(color: .black, radius: 1)
                        .padding(inset)
                        .frame(
                            width: rect.width,
                            height: rect.height,
                            alignment: overlayAlignment(vm.overlay.position)
                        )
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Aspect-fit (letterbox/pillarbox) rect for a video of `aspect` inside a
    /// container — the resize-aspect geometry AVPlayerView uses, computed so we
    /// stay in pure SwiftUI coordinates.
    private func fittedVideoRect(in container: CGSize, aspect: CGFloat) -> CGRect {
        guard container.width > 0, container.height > 0, aspect > 0 else { return .zero }
        var w = container.width
        var h = container.height
        if container.width / container.height > aspect {
            w = container.height * aspect          // pillarbox — height fills
        } else {
            h = container.width / aspect           // letterbox — width fills
        }
        return CGRect(
            x: (container.width - w) / 2,
            y: (container.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func overlayAlignment(_ position: OverlayPosition) -> Alignment {
        switch position {
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        }
    }

    private func rebuildStripModel() {
        guard let meta = vm.metadata, let url = vm.sourceURL else {
            stripModel = nil
            return
        }
        let asset = AVURLAsset(url: url)
        let renderer = ThumbnailRenderer(asset: asset)
        let cache = ThumbnailCache(totalCostLimit: ThumbnailCache.tier())
        stripModel = StripModel(
            duration: meta.duration,
            nominalFPS: meta.nominalFrameRate,
            cache: cache,
            renderer: renderer
        )
    }
}
