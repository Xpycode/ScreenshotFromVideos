//
//  Theme.swift
//  ScreenshotFromVideos
//
//  Floor 5 tokens from cookbook 00-app-shell.md §2. Do not redefine the
//  floor values; new tokens may be added (by role, never by value) but
//  primaryBackground / secondaryBackground / accent / primaryText /
//  secondaryText must match across every macOS app in the lineup.
//
//  ThemeManager (the @Observable user-customizable-accent variant in the
//  cookbook) is intentionally omitted for now — Phase 4 doesn't need a
//  user-customizable accent. Add it back here when settings-driven theming
//  becomes a real requirement.
//

import SwiftUI

enum Theme {
    static let primaryBackground: Color = Color(white: 0.10)
    static let secondaryBackground: Color = Color(white: 0.15)
    static let accent: Color = Color(red: 0.9, green: 0.5, blue: 0.2)
    static let primaryText: Color = .white
    static let secondaryText: Color = .white.opacity(0.65)
}
