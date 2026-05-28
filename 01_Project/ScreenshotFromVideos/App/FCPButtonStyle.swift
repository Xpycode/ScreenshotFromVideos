//
//  FCPButtonStyle.swift
//  ScreenshotFromVideos
//
//  Two button styles from the App Shell Standard:
//   - FCPButtonStyle (cookbook 03-appkit-controls.md): the primary style for
//     ordinary buttons and the building block inside FCPSegmented.
//   - FCPToolbarButtonStyle (cookbook 00-app-shell.md §3): for items inside
//     a `.toolbar { }` block, slightly different press animation + stroke.
//

import SwiftUI

/// Primary button style. Used for ordinary buttons and inside FCPSegmented.
struct FCPButtonStyle: ButtonStyle {
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(isOn ? .white : .primary)
            .background(isOn ? Color.accentColor
                              : Color(nsColor: .gray.withAlphaComponent(0.25)))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.25), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Toolbar button style — bind isOn so it animates on toggle.
struct FCPToolbarButtonStyle: ButtonStyle {
    @Binding var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundColor(isOn ? .white : .primary)
            .background(
                ZStack {
                    if isOn {
                        Theme.accent
                    } else {
                        Color(nsColor: .gray.withAlphaComponent(0.2))
                    }
                    if configuration.isPressed {
                        Color.black.opacity(0.2)
                    }
                }
            )
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isOn)
    }
}
