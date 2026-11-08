//
//  AppearanceCommands.swift
//  ScreenshotFromVideos
//
//  Top-level Appearance menu (Match System / Light / Dark), same pattern as
//  Conjoyn's `AppearanceCommands` minus its App Icon section.
//

import SwiftUI
import AppKit

/// User appearance preference, persisted via `@AppStorage(AppearancePreference.storageKey)`.
/// `.auto` follows the system; `.light` / `.dark` pin the app.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case auto, light, dark

    static let storageKey = "appearancePreference"
    static let defaultValue: AppearancePreference = .dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:  return "Match System"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }

    /// Applied app-wide via `NSApp.appearance` (`nil` follows the system) rather
    /// than `.preferredColorScheme`, whose `nil` case does not clear a previously
    /// forced window appearance on macOS. Also covers the Help window, which is a
    /// standalone NSWindow outside the SwiftUI scene.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }

    /// The persisted preference, readable before SwiftUI is up (AppDelegate).
    static var stored: AppearancePreference {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppearancePreference.init(rawValue:)) ?? defaultValue
    }
}

/// A `Commands` struct bound to the App's `@AppStorage` (not an inline closure)
/// so the menu checkmarks stay in sync — same reason as `UpdaterCommands`.
struct AppearanceCommands: Commands {
    @Binding var appearance: AppearancePreference

    var body: some Commands {
        CommandMenu("Appearance") {
            Picker(selection: $appearance) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        }
    }
}
