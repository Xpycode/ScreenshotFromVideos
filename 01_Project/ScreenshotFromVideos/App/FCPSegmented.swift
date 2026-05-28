//
//  FCPSegmented.swift
//  ScreenshotFromVideos
//
//  HStack of FCPButtonStyle buttons — replaces SwiftUI's Picker(.segmented)
//  and AppKit's NSSegmentedControl (both render Tahoe-redesigned on macOS 26).
//  Spec from cookbook 03-appkit-controls.md.
//

import SwiftUI

struct FCPSegmented<T: Hashable>: View {
    let items: [(label: String, value: T)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                Button(item.label) { selection = item.value }
                    .buttonStyle(FCPButtonStyle(isOn: selection == item.value))
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        enum Mode: Hashable { case interval, manual }
        @State var mode: Mode = .interval
        var body: some View {
            FCPSegmented(
                items: [("Interval", Mode.interval), ("Manual", Mode.manual)],
                selection: $mode
            )
            .padding()
        }
    }
    return PreviewWrapper()
}
