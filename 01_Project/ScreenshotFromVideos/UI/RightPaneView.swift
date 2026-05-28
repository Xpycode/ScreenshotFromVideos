//
//  RightPaneView.swift
//  ScreenshotFromVideos
//
//  Inspector side of the HSplitView shell. Sections (each separated by a
//  Divider with vertical padding):
//    1. Mode picker (Interval / Manual)
//    2. Interval params      (visible when tab == .interval)
//    3. Manual timestamps    (visible when tab == .manual)
//    4. Output folder
//    5. Options (toggles + DisclosureGroup for advanced)
//    6. Export footer (progress, per-frame caption, Export / Cancel)
//
//  Pane is width-constrained per cookbook 02-layout-templates.md (right
//  inspector ≈ 320–480 pt).
//

import SwiftUI
import CoreMedia

struct RightPaneView: View {
    @Bindable var vm: ExtractionViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modeSection
                    sectionDivider

                    if vm.tab == .interval {
                        intervalSection
                        sectionDivider
                    } else {
                        manualSection
                        sectionDivider
                    }

                    outputSection
                    sectionDivider

                    formatSection
                    sectionDivider

                    optionsSection
                }
                .padding(16)
            }

            exportFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.secondaryBackground)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 480)
        .background(Theme.primaryBackground)
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 8)
    }

    // MARK: - 1. Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Mode")
            FCPSegmented(
                items: [
                    ("Interval", ExtractionTab.interval),
                    ("Manual", ExtractionTab.manual),
                ],
                selection: $vm.tab
            )
        }
    }

    // MARK: - 2. Interval

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Interval")

            FCPSegmented(
                items: [
                    ("Seconds", IntervalUnit.seconds),
                    ("Frames", IntervalUnit.frames),
                ],
                selection: $vm.intervalUnit
            )

            HStack(spacing: 8) {
                switch vm.intervalUnit {
                case .seconds:
                    TextField("Seconds", value: $vm.intervalSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("seconds")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                case .frames:
                    TextField("Frames", value: $vm.intervalFrames, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("frames")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let hint = intervalHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var intervalHint: String? {
        guard let fps = vm.metadata?.nominalFrameRate, fps > 0 else { return nil }
        switch vm.intervalUnit {
        case .seconds:
            guard vm.intervalSeconds > 0 else { return nil }
            let frames = Int((vm.intervalSeconds * Double(fps)).rounded())
            return "≈ every \(frames) frames at \(Int(fps.rounded())) fps"
        case .frames:
            guard vm.intervalFrames > 0 else { return nil }
            let seconds = Double(vm.intervalFrames) / Double(fps)
            return String(format: "≈ every %.2fs at %d fps", seconds, Int(fps.rounded()))
        }
    }

    // MARK: - 3. Manual timestamps

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Manual timestamps")

            if vm.manualTimes.isEmpty {
                Text("Scrub the player and press ⌘C to capture frames.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(vm.manualTimes.enumerated()), id: \.offset) { index, time in
                        HStack {
                            Text(TimestampFormatter.string(from: time))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Theme.primaryText)
                            Spacer()
                            Button {
                                vm.removeManualTime(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.secondaryBackground)
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - 4. Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Output folder")

            HStack(spacing: 8) {
                Text(vm.outputFolder?.path ?? "no folder chosen")
                    .font(.caption)
                    .foregroundStyle(vm.outputFolder == nil ? Theme.secondaryText : Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change…") {
                    if let url = FilePickers.pickOutputFolder() {
                        vm.setOutputFolder(url)
                    }
                }
                .buttonStyle(FCPButtonStyle())
            }
        }
    }

    // MARK: - 5. Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Options")

            Toggle("Burn timestamp into image", isOn: $vm.overlay.enabled)
            Toggle("Number filenames sequentially", isOn: $vm.numbering.enabled)

            DisclosureGroup("Options…") {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timestamp position")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        FCPSegmented(
                            items: [
                                ("\u{2196}", OverlayPosition.topLeft),
                                ("\u{2197}", OverlayPosition.topRight),
                                ("\u{2199}", OverlayPosition.bottomLeft),
                                ("\u{2198}", OverlayPosition.bottomRight),
                            ],
                            selection: $vm.overlay.position
                        )
                        .disabled(!vm.overlay.enabled)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font size")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("\(Int(vm.overlay.fontSize))pt")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Slider(value: $vm.overlay.fontSize, in: 16...96)
                            .disabled(!vm.overlay.enabled)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filename pattern")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Pattern", text: $vm.numbering.templater.pattern)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!vm.numbering.enabled)
                            .help(filenameTokensHelp)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var filenameTokensHelp: String {
        """
        Available tokens:
        {name} — source video filename
        {counter} — zero-padded counter (0001, 0002…)
        {index} — un-padded 1-based index
        {date} — YYYY-MM-DD at export time
        {time} — HH-MM-SS at export time
        """
    }

    // MARK: - 5b. Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Format")

            HStack(spacing: 6) {
                ForEach(ExportFormat.allCases) { fmt in
                    Button(fmt.rawValue) { vm.exportFormat = fmt }
                        .buttonStyle(.bordered)
                        .tint(vm.exportFormat == fmt ? .accentColor : .secondary)
                        .controlSize(.small)
                }
            }

            if vm.exportFormat.supportsCompression {
                HStack(spacing: 8) {
                    Text("Quality")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                    Slider(value: $vm.exportQuality, in: 0.1...1.0, step: 0.05)
                        .controlSize(.small)
                    Text("\(Int((vm.exportQuality * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - 6. Export footer

    private var exportFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.metadata != nil && !vm.isRunning {
                let n = vm.previewFrameCount
                Text("\(n) frame\(n == 1 ? "" : "s") will be exported")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            if vm.isRunning, let p = vm.progress {
                ProgressView(value: vm.progressFraction)
                    .progressViewStyle(.linear)
                Text("\(p.completed)/\(p.total) — \(p.lastWritten?.lastPathComponent ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if vm.isRunning {
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
            } else if !vm.statusMessage.isEmpty {
                Text(vm.statusMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("Export") {
                    vm.startExtraction()
                }
                .buttonStyle(FCPButtonStyle(isOn: vm.canExport))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!vm.canExport)

                if vm.isRunning {
                    Button("Cancel", role: .destructive) {
                        vm.cancel()
                    }
                    .buttonStyle(FCPButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
    }
}
