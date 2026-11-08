//
//  Theme.swift
//  ScreenshotFromVideos
//
//  Floor 5 tokens from cookbook 00-app-shell.md §2. Do not redefine the
//  floor values; new tokens may be added (by role, never by value) but
//  primaryBackground / secondaryBackground / accent / primaryText /
//  secondaryText must match across every macOS app in the lineup.
//
//  Tokens are **adaptive** (2026-11-08, step 4): each `Color` resolves against
//  the window's live `NSAppearance`, so the Appearance menu (Match System /
//  Light / Dark) flips the whole UI by setting `NSApp.appearance`. The dark
//  values are the unchanged floor; the light values follow Conjoyn's "soft
//  neutral gray" palette (light gray surfaces, not pure white). `accent` is
//  mode-independent — it is only used as a fill, never as foreground text.
//

import SwiftUI
import AppKit

enum Theme {
    static let primaryBackground = Color(light: 0xF4F4F4, dark: 0x1A1A1A)   // dark = white 0.10
    static let secondaryBackground = Color(light: 0xE6E6E6, dark: 0x262626) // dark = white 0.15
    static let accent: Color = Color(red: 0.9, green: 0.5, blue: 0.2)
    static let primaryText = Color(light: 0x1E1E1E, dark: 0xFFFFFF)
    static let secondaryText = Color(light: 0x5A5A5A, dark: 0xFFFFFF, darkAlpha: 0.65)

    /// Empty (still-decoding) thumbnail cell. Darker than `secondaryBackground`
    /// in both modes so empty cells read as "loading", not "void".
    static let emptyCell = Color(light: 0xD2D2D2, dark: 0x121212)           // dark = white 0.07
}

extension Color {
    /// Adaptive color from two sRGB hex literals — resolves `light` in an Aqua
    /// appearance, `dark` otherwise (against the window's live `NSAppearance`).
    init(light: UInt32, dark: UInt32, darkAlpha: CGFloat = 1) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isLight
                ? NSColor(srgbHex: light)
                : NSColor(srgbHex: dark).withAlphaComponent(darkAlpha)
        })
    }
}

private extension NSColor {
    /// Opaque sRGB color from a 24-bit hex literal.
    convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension NSAppearance {
    /// True for the Aqua (light) family.
    var isLight: Bool {
        bestMatch(from: [.aqua, .darkAqua]) != .darkAqua
    }
}
