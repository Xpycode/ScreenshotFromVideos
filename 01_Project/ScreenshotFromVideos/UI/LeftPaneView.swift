//
//  LeftPaneView.swift
//  ScreenshotFromVideos
//
//  Left side of the HSplitView shell. Two states:
//   - Empty:   drop hint + "Pick video…" button (NSOpenPanel).
//   - Loaded:  PlayerView fills the pane; below it a footer row with the
//              live current-time label, the Capture-this-frame button
//              (⌘C), and a captured-count label.
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
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Remove video")

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
                Text(currentTimeString)
                    .font(.system(size: 13, weight: .thin).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }

            Spacer()

            Button("Capture this frame") {
                vm.captureCurrentFrame()
            }
            .buttonStyle(FCPButtonStyle())
            .keyboardShortcut("c", modifiers: .command)

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
